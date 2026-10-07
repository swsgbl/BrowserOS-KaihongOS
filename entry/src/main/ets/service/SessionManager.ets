import { SessionRecord, OperationLog, ScreenshotEntry } from '../model/SessionRecord'
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { ConfigManager } from '../storage/ConfigManager'
import { RecordingQuality } from '../common/Types'
import { ScreenshotCapture } from '../protocol/ScreenshotCapture'
import { TabManager } from './TabManager'

interface SessionStartData {
  sessionId: string
  agentId: string
}

class SessionManagerImpl {
  private activeSessions: Map<string, SessionRecord> = new Map()
  private recordingTimers: Map<string, number> = new Map()
  private maxStorageSpace: number = Constants.RECORDING_MAX_SPACE_MB * 1024 * 1024
  private sessionTabs: Map<string, string> = new Map()
  /** P9r: 磁盘枚举的历史会话（仅元数据，screenshots 置空省内存；回放走 getSessionDetail 重读盘） */
  private persistedSessions: SessionRecord[] = []
  private persistedLoading: boolean = false
  private persistedReady: boolean = false

  startRecording(agentId: string, tabId: string = ''): SessionRecord | null {
    const sessionId = this.generateSessionId()
    const session = new SessionRecord(sessionId, agentId)

    this.activeSessions.set(sessionId, session)
    if (tabId.length > 0) {
      this.sessionTabs.set(sessionId, tabId)
    }
    const startData: SessionStartData = { sessionId: sessionId, agentId: agentId }
    EventBus.emit(EventBusEvents.SESSION_RECORDING_START, startData)

    this.startRecordingTimer(sessionId, agentId)
    console.info('[SessionManager] startRecording session=' + sessionId + ' agent=' + agentId + ' tab=' + tabId)

    return session
  }

  stopRecording(sessionId: string): SessionRecord | null {
    const session = this.activeSessions.get(sessionId)
    if (!session) {
      return null
    }

    session.endSession()
    this.stopRecordingTimer(sessionId)

    this.persistSession(session)
    if (!this.persistedSessions.some((s: SessionRecord) => s.sessionId === sessionId)) {
      this.persistedSessions.push(session)
    }
    this.activeSessions.delete(sessionId)
    this.sessionTabs.delete(sessionId)

    EventBus.emit(EventBusEvents.SESSION_RECORDING_STOP, session.toJSON())
    return session
  }

  /** P9r: 异步枚举 sessions/*.json 元数据（截图字段跳过） */
  async ensurePersistedSessions(): Promise<void> {
    if (this.persistedReady || this.persistedLoading) {
      return
    }
    this.persistedLoading = true
    try {
      const files = await StorageManager.listDir('sessions')
      const jsonFiles = files.filter((f: string) => f.endsWith('.json')).sort().reverse()
      const loaded: SessionRecord[] = []
      for (const f of jsonFiles) {
        const content = await StorageManager.load('sessions/' + f)
        if (!content) {
          continue
        }
        try {
          const json = JSON.parse(content) as Record<string, Object>
          const rec = SessionRecord.fromJSON(json)
          rec.screenshots = []
          loaded.push(rec)
        } catch (e) {
          console.warn('[SessionManager] skip corrupted session file: ' + f)
        }
      }
      this.persistedSessions = loaded
      this.persistedReady = true
      console.info('[SessionManager] persisted sessions loaded: ' + loaded.length)
    } finally {
      this.persistedLoading = false
    }
  }

  /** P9r: 活跃内存会话 + 磁盘历史会话合并去重（sessionId，活跃优先，startTime 降序） */
  getSessionList(): SessionRecord[] {
    const merged: SessionRecord[] = []
    const seen = new Set<string>()
    for (const s of this.activeSessions.values()) {
      seen.add(s.sessionId)
      merged.push(s)
    }
    for (const s of this.persistedSessions) {
      if (!seen.has(s.sessionId)) {
        seen.add(s.sessionId)
        merged.push(s)
      }
    }
    merged.sort((a: SessionRecord, b: SessionRecord): number => b.startTime - a.startTime)
    return merged
  }

  async getSessionListAsync(): Promise<SessionRecord[]> {
    await this.ensurePersistedSessions()
    return this.getSessionList()
  }

  async getSessionDetail(sessionId: string): Promise<SessionRecord | null> {
    const activeSession = this.activeSessions.get(sessionId)
    if (activeSession) {
      return activeSession
    }

    const content = await StorageManager.load(`sessions/${sessionId}.json`)
    if (content) {
      try {
        const json = JSON.parse(content) as Record<string, Object>
        return SessionRecord.fromJSON(json)
      } catch (e) {
        return null
      }
    }
    return null
  }

  async deleteSession(sessionId: string): Promise<boolean> {
    this.stopRecordingTimer(sessionId)
    this.activeSessions.delete(sessionId)
    this.persistedSessions = this.persistedSessions.filter((s: SessionRecord) => s.sessionId !== sessionId)
    return StorageManager.delete(`sessions/${sessionId}.json`)
  }

  createReplayer(sessionId: string): SessionReplayer | null {
    const session = this.activeSessions.get(sessionId)
    if (session) {
      return new SessionReplayer(session)
    }
    return null
  }

  async createReplayerAsync(sessionId: string): Promise<SessionReplayer | null> {
    const session = await this.getSessionDetail(sessionId)
    if (session) {
      return new SessionReplayer(session)
    }
    return null
  }

  setStoragePath(path: string): void {
    StorageManager.setBasePath(path)
  }

  setMaxStorageSpace(maxSpaceMb: number): void {
    this.maxStorageSpace = maxSpaceMb * 1024 * 1024
  }

  addOperationLog(sessionId: string, log: OperationLog): void {
    const session = this.activeSessions.get(sessionId)
    if (session) {
      session.addOperationLog(log)
    }
  }

  addScreenshot(sessionId: string, screenshot: ScreenshotEntry): void {
    const session = this.activeSessions.get(sessionId)
    if (session) {
      session.addScreenshot(screenshot)
    }
  }

  addUrlChange(sessionId: string, url: string): void {
    const session = this.activeSessions.get(sessionId)
    if (session) {
      session.addUrl(url)
    }
  }

  private startRecordingTimer(sessionId: string, agentId: string): void {
    const quality = ConfigManager.get().recordingQuality
    const interval = Constants.RECORDING_INTERVAL_MAP[quality] || 2000

    const timerId = setInterval(() => {
      this.captureRecordingData(sessionId, agentId)
    }, interval)
    this.recordingTimers.set(sessionId, timerId)
  }

  private stopRecordingTimer(sessionId: string): void {
    const timer = this.recordingTimers.get(sessionId)
    if (timer) {
      clearInterval(timer)
      this.recordingTimers.delete(sessionId)
    }
  }

  private async captureRecordingData(sessionId: string, agentId: string): Promise<void> {
    const session = this.activeSessions.get(sessionId)
    if (!session) {
      return
    }

    // URL from the agent tab
    let url = ''
    const tabId = this.sessionTabs.get(sessionId) || ''
    if (tabId.length > 0) {
      const tab = TabManager.getTab(tabId)
      if (tab !== null && tab.currentUrl) {
        url = tab.currentUrl
      }
    }
    if (url.length > 0) {
      const lastUrl = session.urlSequence.length > 0 ? session.urlSequence[session.urlSequence.length - 1] : ''
      if (url !== lastUrl) {
        session.addUrl(url)
      }
    }

    // Screenshot via ScreenshotCapture (guarantees data: prefix)
    const quality = ConfigManager.get().recordingQuality
    const r = await ScreenshotCapture.capture(quality)
    if (r.success && r.data) {
      session.addScreenshot(new ScreenshotEntry(r.data, url))
      console.info('[SessionManager] capture shot#' + session.screenshots.length + ' url=' + url + ' size=' + r.data.length)
    } else {
      console.warn('[SessionManager] capture failed: ' + (r.error || 'no data'))
    }

    this.checkStorageSpace()
  }

  private async checkStorageSpace(): Promise<void> {
    const usedSpace = await StorageManager.checkSpace()
    if (usedSpace > this.maxStorageSpace) {
      await this.cleanupOldSessions()
    }
  }

  private async cleanupOldSessions(): Promise<void> {
    const files = await StorageManager.listDir('sessions')
    if (files.length === 0) {
      return
    }

    const sortedFiles = files.sort()
    const toDelete = Math.ceil(sortedFiles.length * 0.2)

    for (let i = 0; i < toDelete; i++) {
      await StorageManager.delete(`sessions/${sortedFiles[i]}`)
    }
  }

  private async persistSession(session: SessionRecord): Promise<void> {
    try {
      const filePath = `sessions/${session.sessionId}.json`
      await StorageManager.saveJSON(filePath, session.toJSON())
      session.filePath = `${Constants.SESSIONS_PATH}${session.sessionId}.json`
    } catch (e) {
      ErrorHandler.handle(new AppError(ErrorCodes.SES_001, `Session persist failed: ${e}`))
    }
  }

  private generateSessionId(): string {
    return `ses_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`
  }
}

class SessionReplayer {
  private session: SessionRecord
  private currentTime: number = 0
  private isPlaying: boolean = false
  private speed: number = 1
  private playTimer: number | null = null

  constructor(session: SessionRecord) {
    this.session = session
  }

  play(): void {
    this.isPlaying = true
    this.scheduleNextFrame()
  }

  pause(): void {
    this.isPlaying = false
    if (this.playTimer) {
      clearTimeout(this.playTimer)
      this.playTimer = null
    }
  }

  stop(): void {
    this.pause()
    this.currentTime = 0
  }

  seekTo(timeMs: number): void {
    this.currentTime = Math.max(0, Math.min(timeMs, this.session.duration))
  }

  setSpeed(speed: number): void {
    this.speed = speed
  }

  getSpeed(): number {
    return this.speed
  }

  isPlayingState(): boolean {
    return this.isPlaying
  }

  getCurrentTime(): number {
    return this.currentTime
  }

  getDuration(): number {
    return this.session.duration
  }

  getScreenshots(): ScreenshotEntry[] {
    return this.session.screenshots
  }

  getOperationLogs(): OperationLog[] {
    return this.session.operationLogs
  }

  getCurrentScreenshot(): ScreenshotEntry | null {
    const screenshots = this.session.screenshots
    for (let i = screenshots.length - 1; i >= 0; i--) {
      if (screenshots[i].timestamp <= this.session.startTime + this.currentTime) {
        return screenshots[i]
      }
    }
    return screenshots.length > 0 ? screenshots[0] : null
  }

  getCurrentOperations(): OperationLog[] {
    const operations = this.session.operationLogs
    const targetTime = this.session.startTime + this.currentTime
    return operations.filter(op => op.timestamp <= targetTime)
  }

  private scheduleNextFrame(): void {
    if (!this.isPlaying) {
      return
    }
    const intervalMs = 100 / this.speed
    this.playTimer = setTimeout(() => {
      this.currentTime += intervalMs * this.speed
      if (this.currentTime >= this.session.duration) {
        this.currentTime = this.session.duration
        this.isPlaying = false
        return
      }
      this.scheduleNextFrame()
    }, intervalMs)
  }
}

export const SessionManager = new SessionManagerImpl()
export { SessionReplayer }