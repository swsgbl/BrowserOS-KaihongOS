import { SessionRecord, OperationLog, ScreenshotEntry } from '../model/SessionRecord'
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { ConfigManager } from '../storage/ConfigManager'
import { RecordingQuality } from '../common/Types'

interface SessionStartData {
  sessionId: string
  agentId: string
}

class SessionManagerImpl {
  private activeSessions: Map<string, SessionRecord> = new Map()
  private recordingTimers: Map<string, number> = new Map()
  private maxStorageSpace: number = Constants.RECORDING_MAX_SPACE_MB * 1024 * 1024

  startRecording(agentId: string): SessionRecord | null {
    const sessionId = this.generateSessionId()
    const session = new SessionRecord(sessionId, agentId)

    this.activeSessions.set(sessionId, session)
    const startData: SessionStartData = { sessionId: sessionId, agentId: agentId }
    EventBus.emit(EventBusEvents.SESSION_RECORDING_START, startData)

    this.startRecordingTimer(sessionId, agentId)

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
    this.activeSessions.delete(sessionId)

    EventBus.emit(EventBusEvents.SESSION_RECORDING_STOP, session.toJSON())
    return session
  }

  getSessionList(): SessionRecord[] {
    return Array.from(this.activeSessions.values())
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
    return StorageManager.delete(`sessions/${sessionId}.json`)
  }

  createReplayer(sessionId: string): SessionReplayer | null {
    const session = this.activeSessions.get(sessionId)
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

  private captureRecordingData(sessionId: string, agentId: string): void {
    const session = this.activeSessions.get(sessionId)
    if (!session) {
      return
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