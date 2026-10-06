// P4 relay2 patcher v2: CRLF-aware, escape inner backticks/dollar-brace in template wrappers
const fs = require('fs');

function patch(file, patches) {
  let text = fs.readFileSync(file, 'utf8');
  for (const p of patches) {
    const oldS = p.old.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');
    const newS = p.new.replace(/\r\n/g, '\n').replace(/\n/g, '\r\n');
    const count = text.split(oldS).length - 1;
    if (count !== 1) {
      console.error('FAIL [' + file + '] anchor hits=' + count + ' head: ' + JSON.stringify(p.old.slice(0, 70)));
      process.exit(1);
    }
    text = text.replace(oldS, newS);
  }
  fs.writeFileSync(file, text, 'utf8');
  console.log('OK ' + file + ' (' + patches.length + ' patches)');
}

const B = 'D:\\BrowserOS - KaihongOS\\entry\\src\\main\\ets\\';

// ---------- A. HttpMcpTransport: GET loose framing ----------
patch(B + 'service\\HttpMcpTransport.ets', [
  {
    old: `      const headerEnd = this.findHeaderEnd(buf)
      if (headerEnd < 0) {
        if (buf.length > MAX_HEADER_BYTES) {`,
    new: `      let headerEnd = this.findHeaderEnd(buf)
      let loose = false
      if (headerEnd < 0) {
        // P4 fix: GET carries no body; some clients never deliver the standard CRLFCRLF terminator.
        // Loose fallback: request line complete + method GET + no Content-Length + buffer ends with LF
        const firstLineEnd = this.findFirstLineEnd(buf)
        if (firstLineEnd > 0) {
          const reqLineText = this.decodeUtf8(buf.subarray(0, firstLineEnd))
          const method = reqLineText.split(' ')[0] || ''
          const cl = this.parseContentLength(this.decodeUtf8(buf))
          const endsWithLf = buf.length > 0 && buf[buf.length - 1] === 10
          if (method === 'GET' && cl === 0 && endsWithLf) {
            headerEnd = buf.length - 1
            loose = true
            console.warn(\`[\${TAG}] loose GET framing (no CRLFCRLF, tail=LF), treat \${buf.length}B as header\`)
          }
        }
        if (headerEnd < 0) {
          if (buf.length > MAX_HEADER_BYTES) {`
  },
  {
    old: `          conn.buffer = new Uint8Array(0)
          return
        }
        break
      }
      const headerText = this.decodeUtf8(buf.subarray(0, headerEnd))
      const contentLength = this.parseContentLength(headerText)`,
    new: `          conn.buffer = new Uint8Array(0)
          return
        }
          let tailHex = ''
          const tailStart = Math.max(0, buf.length - 16)
          for (let k = tailStart; k < buf.length; k++) {
            tailHex += buf[k].toString(16).padStart(2, '0') + ' '
          }
          console.warn(\`[\${TAG}] header end not found (len=\${buf.length} tail=\${tailHex.trim()}), waiting\`)
          break
        }
      }
      const headerText = this.decodeUtf8(buf.subarray(0, headerEnd))
      const contentLength = loose ? 0 : this.parseContentLength(headerText)`
  },
  {
    old: `      const total = headerEnd + 4 + contentLength`,
    new: `      const total = loose ? buf.length : headerEnd + 4 + contentLength`
  },
  {
    old: `      const bodyText = this.decodeUtf8(buf.subarray(headerEnd + 4, total))`,
    new: `      const bodyText = loose ? '' : this.decodeUtf8(buf.subarray(headerEnd + 4, total))`
  },
  {
    old: `  private parseContentLength(headerText: string): number {`,
    new: `  private findFirstLineEnd(buf: Uint8Array): number {
    for (let i = 0; i + 1 < buf.length; i++) {
      if (buf[i] === 13 && buf[i + 1] === 10) {
        return i
      }
    }
    return -1
  }

  private parseContentLength(headerText: string): number {`
  }
]);

// ---------- B. SessionManager ----------
patch(B + 'service\\SessionManager.ets', [
  {
    old: `import { RecordingQuality } from '../common/Types'`,
    new: `import { RecordingQuality } from '../common/Types'
import { ScreenshotCapture } from '../protocol/ScreenshotCapture'
import { TabManager } from './TabManager'`
  },
  {
    old: `  private maxStorageSpace: number = Constants.RECORDING_MAX_SPACE_MB * 1024 * 1024

  startRecording(agentId: string): SessionRecord | null {
    const sessionId = this.generateSessionId()
    const session = new SessionRecord(sessionId, agentId)

    this.activeSessions.set(sessionId, session)
    const startData: SessionStartData = { sessionId: sessionId, agentId: agentId }
    EventBus.emit(EventBusEvents.SESSION_RECORDING_START, startData)

    this.startRecordingTimer(sessionId, agentId)

    return session
  }`,
    new: `  private maxStorageSpace: number = Constants.RECORDING_MAX_SPACE_MB * 1024 * 1024
  private sessionTabs: Map<string, string> = new Map()

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
  }`
  },
  {
    old: `    this.persistSession(session)
    this.activeSessions.delete(sessionId)

    EventBus.emit(EventBusEvents.SESSION_RECORDING_STOP, session.toJSON())`,
    new: `    this.persistSession(session)
    this.activeSessions.delete(sessionId)
    this.sessionTabs.delete(sessionId)

    EventBus.emit(EventBusEvents.SESSION_RECORDING_STOP, session.toJSON())`
  },
  {
    old: `  setStoragePath(path: string): void {`,
    new: `  async createReplayerAsync(sessionId: string): Promise<SessionReplayer | null> {
    const session = await this.getSessionDetail(sessionId)
    if (session) {
      return new SessionReplayer(session)
    }
    return null
  }

  setStoragePath(path: string): void {`
  },
  {
    old: `  private captureRecordingData(sessionId: string, agentId: string): void {
    const session = this.activeSessions.get(sessionId)
    if (!session) {
      return
    }

    this.checkStorageSpace()
  }`,
    new: `  private async captureRecordingData(sessionId: string, agentId: string): Promise<void> {
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
  }`
  }
]);

// ---------- C. Constants ----------
patch(B + 'common\\Constants.ets', [
  {
    old: `    'medium': 2000,`,
    new: `    'medium': 3000,`
  }
]);

// ---------- D. AgentEngine ----------
patch(B + 'service\\AgentEngine.ets', [
  {
    old: `import { BCPResult } from '../common/Types'`,
    new: `import { BCPResult } from '../common/Types'
import { SessionManager } from './SessionManager'
import { OperationLog } from '../model/SessionRecord'`
  },
  {
    old: `  private runningTasks: Set<string> = new Set()`,
    new: `  private runningTasks: Set<string> = new Set()
  private agentSessions: Map<string, string> = new Map()`
  },
  {
    old: `    this.setAgentRunning(agentId)
    this.updateAgentProgress(agentId, 0)`,
    new: `    this.setAgentRunning(agentId)
    this.updateAgentProgress(agentId, 0)

    // P4: start session recording
    const session = SessionManager.startRecording(agentId, config.tabId)
    if (session) {
      this.agentSessions.set(agentId, session.sessionId)
    }`
  },
  {
    old: `            messages.push(LLMChatMessage.toolResult(call.id, resultText))`,
    new: `            messages.push(LLMChatMessage.toolResult(call.id, resultText))

            // P4: record operation log
            const sid = this.agentSessions.get(agentId)
            if (sid) {
              const argsPreview = call.function_args.length > 60 ? call.function_args.substring(0, 60) : call.function_args
              const resultPreview = resultText.length > 100 ? resultText.substring(0, 100) : resultText
              SessionManager.addOperationLog(sid, new OperationLog(call.function_name, argsPreview,
                result.success ? 'success' : 'fail', resultPreview))
              console.info('[AgentEngine] addOperationLog tool=' + call.function_name + ' result=' + (result.success ? 'success' : 'fail'))
              if (result.success && call.function_name === 'navigate') {
                try {
                  const navArgs = JSON.parse(call.function_args) as Record<string, Object>
                  const navUrl = this.argStr(navArgs, 'url')
                  if (navUrl.length > 0) {
                    SessionManager.addUrlChange(sid, navUrl)
                  }
                } catch (e2) {
                  console.warn('[AgentEngine] navigate url parse failed')
                }
              }
            }`
  },
  {
    old: `      this.setAgentCompleted(agentId)
    }
  }

  private receivedAnswer(messages: LLMChatMessage[]): boolean {`,
    new: `      this.setAgentCompleted(agentId)
    }

    // P4: stop recording and persist (keep agentId->sessionId mapping for replay entry)
    const sid2 = this.agentSessions.get(agentId)
    if (sid2) {
      SessionManager.stopRecording(sid2)
    }
  }

  private receivedAnswer(messages: LLMChatMessage[]): boolean {`
  },
  {
    old: `  getAgentActivity(agentId: string): string {
    return this.agentActivities.get(agentId) || ''
  }`,
    new: `  getAgentActivity(agentId: string): string {
    return this.agentActivities.get(agentId) || ''
  }

  /** P4: latest session id of the agent ('' if none) */
  getSessionId(agentId: string): string {
    return this.agentSessions.get(agentId) || ''
  }`
  }
]);

// ---------- E. SessionPlayerPage ----------
patch(B + 'pages\\SessionPlayerPage.ets', [
  {
    old: `import { Constants } from '../common/Constants'`,
    new: `import { Constants } from '../common/Constants'
import { router } from '@kit.ArkUI'`
  },
  {
    old: `  aboutToAppear(): void {
    if (this.sessionId) {
      this.loadSession()
    }
  }`,
    new: `  aboutToAppear(): void {
    const p = router.getParams() as Record<string, Object>
    if (p && p['sessionId'] !== undefined) {
      const v = p['sessionId'] as string
      if (v && v.length > 0) {
        this.sessionId = v
      }
    }
    if (this.sessionId) {
      this.loadSession()
    }
  }`
  },
  {
    old: `      this.replayer = SessionManager.createReplayer(this.sessionId)`,
    new: `      console.info('[SessionPlayer] loaded session=' + this.sessionId
        + ' shots=' + (session ? session.screenshots.length : 0)
        + ' logs=' + (session ? session.operationLogs.length : 0))
      this.replayer = await SessionManager.createReplayerAsync(this.sessionId)`
  }
]);

// ---------- F. NeoDashboardPage ----------
patch(B + 'pages\\NeoDashboardPage.ets', [
  {
    old: `                if (status.status === AgentStatus.ERROR && status.errorMessage.length > 0) {`,
    new: `                if (status.status === AgentStatus.COMPLETED || status.status === AgentStatus.ERROR) {
                  Button('\u56de\u653e')
                    .fontSize(10)
                    .height(24)
                    .backgroundColor('#FF9800')
                    .margin({ top: 4 })
                    .onClick(() => {
                      const sid = AgentEngine.getSessionId(status.agentId)
                      if (sid.length > 0) {
                        const navParams: Record<string, Object> = { 'sessionId': sid }
                        router.pushUrl({ url: 'pages/SessionPlayerPage', params: navParams })
                      }
                    })
                }

                if (status.status === AgentStatus.ERROR && status.errorMessage.length > 0) {`
  }
]);

console.log('ALL PATCHES APPLIED');
