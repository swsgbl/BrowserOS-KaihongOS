import { AgentConfig } from '../model/AgentConfig'
import { AgentStatusInfo } from '../model/AgentStatus'
import { AgentStatus, RunStrategy } from '../common/Types'
import { TabManager } from './TabManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { ConfigManager } from '../storage/ConfigManager'
import { LLMClient, LLMChatMessage, LLMToolCall, LLMToolSpec, LLMParamProp, LLMParamEntry, LLMParamsSchema } from './LLMClient'
import { BCPEngine } from '../protocol/BCPEngine'
import { JSBridgeInjector } from '../protocol/JSBridgeInjector'
import { SensitiveOperationDetector } from './SensitiveOperationDetector'
import { BCPResult } from '../common/Types'
import { SessionManager } from './SessionManager'
import { OperationLog } from '../model/SessionRecord'

type StatusChangeCallback = (agentId: string, status: AgentStatus) => void

interface AgentTimeoutErrorData {
  code: string
  message: string
  agentId: string
}

/** BCPResult 的 JSON 序列化形（ArkTS 严格模式：字面量需显式类） */
class BCPResultJSON {
  success: boolean = false
  data: string = ''
  error: string = ''
}

/** BCPResult 可实例化实现 */
class BCPResultImpl implements BCPResult {
  success: boolean = false
  data: string | null = null
  error: string | null = null
}

class AgentEngineImpl {
  private agents: Map<string, AgentConfig> = new Map()
  private agentStatuses: Map<string, AgentStatusInfo> = new Map()
  private statusCallbacks: StatusChangeCallback[] = []
  private heartbeatTimers: Map<string, number> = new Map()
  private timeoutTimers: Map<string, number> = new Map()
  private agentActivities: Map<string, string> = new Map()
  private runningTasks: Set<string> = new Set()
  private agentSessions: Map<string, string> = new Map()
  /** P19a: 终态答案库（完成=最终答复 / 失败=原因），AgentSidePanel 轮询回流用 */
  private finalAnswers: Map<string, string> = new Map()
  /** P24a: 向 agent 绑定 tab 注入/移除页面辉光 overlay(容错: webview 未挂载或换页即静默失败) */
  private __glowStart(agentId: string): void {
    const config0 = this.agents.get(agentId)
    if (!config0) return
    const inst = TabManager.getWebView(config0.tabId)
    if (inst === null || inst.controller === undefined) return
    try {
      inst.controller.runJavaScript(JSBridgeInjector.glowStart())
      console.info('[AgentEngine] glow started on tab ' + config0.tabId)
    } catch (e) {
      console.warn('[AgentEngine] glow start failed: ' + e)
    }
  }

  private __glowStop(agentId: string): void {
    const config0 = this.agents.get(agentId)
    if (!config0) return
    const inst = TabManager.getWebView(config0.tabId)
    if (inst === null || inst.controller === undefined) return
    try {
      inst.controller.runJavaScript(JSBridgeInjector.glowStop())
      console.info('[AgentEngine] glow stopped on tab ' + config0.tabId)
    } catch (e) {
      console.warn('[AgentEngine] glow stop failed: ' + e)
    }
  }

  /** P24a: 查询页面停止钮是否被点击(1s 轮询由 runAgentTask 循环间 await 兜底) */
  private async __glowStopRequested(agentId: string): Promise<boolean> {
    const config0 = this.agents.get(agentId)
    if (!config0) return false
    const inst = TabManager.getWebView(config0.tabId)
    if (inst === null || inst.controller === undefined) return false
    try {
      const r = await inst.controller.runJavaScript(JSBridgeInjector.glowStopRequested())
      return `${r}` === 'true'
    } catch (e) {
      return false
    }
  }

  private static readonly MAX_STEPS: number = 15

  /** P19a: 取任务终态答案（引擎侧保留，面板消费后自行去重） */
  getFinalAnswer(agentId: string): string | null {
    return this.finalAnswers.get(agentId) ?? null
  }
  private static readonly LLM_TIMEOUT_MS: number = 30000

  createAgent(name: string, targetUrl: string, taskDescription: string,
    runStrategy: RunStrategy = RunStrategy.ONCE): AgentConfig | null {
    const maxAgents = ConfigManager.getMaxAgents()
    if (this.agents.size >= maxAgents) {
      ErrorHandler.handle(new AppError(ErrorCodes.AGT_001, `Max agents (${maxAgents}) reached`))
      return null
    }

    const agentId = this.generateAgentId()
    const tab = TabManager.createAgentTab(agentId)
    const config = new AgentConfig(agentId, name, targetUrl, taskDescription, runStrategy, Date.now(), tab.tabId)
    const status = new AgentStatusInfo(agentId)

    this.agents.set(agentId, config)
    this.agentStatuses.set(agentId, status)

    EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())

    this.startHeartbeat(agentId)

    // P2: 创建即自动开跑（异步，不阻塞 UI）；未配置 LLM 时由 runAgentTask 立即置 ERROR
    this.runAgentTask(agentId)

    return config
  }

  terminateAgent(agentId: string): boolean {
    const config = this.agents.get(agentId)
    if (!config) {
      ErrorHandler.handle(new AppError(ErrorCodes.AGT_002, `Agent not found: ${agentId}`))
      return false
    }

    this.stopHeartbeat(agentId)
    this.stopTimeoutTimer(agentId)

    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.STOPPED)
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.STOPPED)
    }

    // P24a: 终止时移除页面辉光(tab 关闭前执行, webview 仍可用)
    this.__glowStop(agentId)

    TabManager.closeTab(config.tabId)

    this.agents.delete(agentId)
    this.agentStatuses.delete(agentId)

    return true
  }

  getAgentStatus(agentId: string): AgentStatusInfo | null {
    return this.agentStatuses.get(agentId) || null
  }

  getAllAgentStatus(): AgentStatusInfo[] {
    return Array.from(this.agentStatuses.values())
  }

  getAgentConfig(agentId: string): AgentConfig | null {
    return this.agents.get(agentId) || null
  }

  getAllAgents(): AgentConfig[] {
    return Array.from(this.agents.values())
  }

  resetAgent(agentId: string): boolean {
    const config = this.agents.get(agentId)
    if (!config) {
      return false
    }

    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.IDLE)
      status.currentUrl = ''
      status.progress = 0
      status.errorMessage = ''
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.IDLE)
    }
    this.agentActivities.delete(agentId)

    return true
  }

  onStatusChange(callback: StatusChangeCallback): void {
    this.statusCallbacks.push(callback)
  }

  removeStatusChangeCallback(callback: StatusChangeCallback): void {
    const idx = this.statusCallbacks.indexOf(callback)
    if (idx >= 0) {
      this.statusCallbacks.splice(idx, 1)
    }
  }

  setAgentRunning(agentId: string): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.RUNNING)
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.RUNNING)
      this.startTimeoutTimer(agentId)
    }
  }

  setAgentCompleted(agentId: string): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.COMPLETED)
      status.progress = 100
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.COMPLETED)
      this.stopTimeoutTimer(agentId)
    }
  }

  setAgentError(agentId: string, errorMessage: string): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.ERROR)
      status.errorMessage = errorMessage
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.ERROR)
      this.stopTimeoutTimer(agentId)
    }
  }

  setAgentPaused(agentId: string): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.PAUSED)
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.PAUSED)
    }
  }

  updateAgentProgress(agentId: string, progress: number, currentUrl: string = ''): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.progress = progress
      if (currentUrl) {
        status.currentUrl = currentUrl
      }
      EventBus.emit(EventBusEvents.AGENT_HEARTBEAT, status.toJSON())
    }
  }

  getAgentCount(): number {
    return this.agents.size
  }

  getRunningAgentCount(): number {
    let count = 0
    for (const status of this.agentStatuses.values()) {
      if (status.status === AgentStatus.RUNNING) {
        count++
      }
    }
    return count
  }

  private startHeartbeat(agentId: string): void {
    const intervalId = setInterval(() => {
      const status = this.agentStatuses.get(agentId)
      if (status && status.status === AgentStatus.RUNNING) {
        status.updateHeartbeat()
        EventBus.emit(EventBusEvents.AGENT_HEARTBEAT, status.toJSON())
      }
    }, Constants.HEARTBEAT_INTERVAL_MS)
    this.heartbeatTimers.set(agentId, intervalId)
  }

  private stopHeartbeat(agentId: string): void {
    const timer = this.heartbeatTimers.get(agentId)
    if (timer) {
      clearInterval(timer)
      this.heartbeatTimers.delete(agentId)
    }
  }

  private startTimeoutTimer(agentId: string): void {
    const timeoutMs = ConfigManager.get().agentTimeoutMinutes * 60 * 1000
    const timerId = setTimeout(() => {
      const status = this.agentStatuses.get(agentId)
      if (status && status.status === AgentStatus.RUNNING) {
        this.setAgentPaused(agentId)
        const errorData: AgentTimeoutErrorData = {
          code: ErrorCodes.AGT_005,
          message: ErrorCodes.getMessage(ErrorCodes.AGT_005),
          agentId: agentId
        }
        EventBus.emit(EventBusEvents.ERROR_OCCURRED, errorData)
      }
    }, timeoutMs)
    this.timeoutTimers.set(agentId, timerId)
  }

  private stopTimeoutTimer(agentId: string): void {
    const timer = this.timeoutTimers.get(agentId)
    if (timer) {
      clearTimeout(timer)
      this.timeoutTimers.delete(agentId)
    }
  }

  private notifyStatusChange(agentId: string, status: AgentStatus): void {
    for (const callback of this.statusCallbacks) {
      try {
        callback(agentId, status)
      } catch (e) {
        console.error(`Status change callback error: ${e}`)
      }
    }
  }

  private generateAgentId(): string {
    return `agent_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`
  }

  getAgentActivity(agentId: string): string {
    return this.agentActivities.get(agentId) || ''
  }

  /** P4: latest session id of the agent ('' if none) */
  getSessionId(agentId: string): string {
    return this.agentSessions.get(agentId) || ''
  }

  private setAgentActivity(agentId: string, activity: string): void {
    this.agentActivities.set(agentId, activity)
    const status = this.agentStatuses.get(agentId)
    if (status) {
      EventBus.emit(EventBusEvents.AGENT_HEARTBEAT, status.toJSON())
    }
  }

  /** 单工具 schema 构造辅助（entries 数组，规避 Record 字面量） */
  private makeSpec(name: string, description: string, entries: LLMParamEntry[], required: string[]): LLMToolSpec {
    const params = new LLMParamsSchema()
    params.entries = entries
    params.required = required
    const spec: LLMToolSpec = { name: name, description: description, parameters: params }
    return spec
  }

  private strProp(desc: string): LLMParamProp {
    return new LLMParamProp('string', desc)
  }

  private numProp(desc: string): LLMParamProp {
    return new LLMParamProp('number', desc)
  }

  private entry(key: string, prop: LLMParamProp): LLMParamEntry {
    return new LLMParamEntry(key, prop)
  }

  /** BCP 工具表（JSON Schema），与 BCPEngine 方法一一对应 */
  getToolSpecs(): LLMToolSpec[] {
    const specs: LLMToolSpec[] = []
    const navEntries: LLMParamEntry[] = [this.entry('url', this.strProp('The URL to navigate to'))]
    specs.push(this.makeSpec('navigate', 'Navigate the webview to a URL', navEntries, ['url']))
    const clickEntries: LLMParamEntry[] = [this.entry('selector', this.strProp('CSS selector of the element'))]
    specs.push(this.makeSpec('click', 'Click an element by CSS selector', clickEntries, ['selector']))
    const typeEntries: LLMParamEntry[] = [
      this.entry('selector', this.strProp('CSS selector of the input element')),
      this.entry('text', this.strProp('Text to type'))
    ]
    specs.push(this.makeSpec('type', 'Type text into an element', typeEntries, ['selector', 'text']))
    specs.push(this.makeSpec('getText', 'Get visible text of the current page', [], []))
    specs.push(this.makeSpec('snapshot', 'Get compact markdown snapshot of the visible page (headings, links, lists, buttons)', [], []))
    const scrollEntries: LLMParamEntry[] = [
      this.entry('deltaX', this.numProp('Horizontal scroll pixels')),
      this.entry('deltaY', this.numProp('Vertical scroll pixels'))
    ]
    specs.push(this.makeSpec('scroll', 'Scroll the page', scrollEntries, ['deltaY']))
    const waitEntries: LLMParamEntry[] = [this.entry('ms', this.numProp('Milliseconds to wait, max 10000'))]
    specs.push(this.makeSpec('wait', 'Wait for milliseconds', waitEntries, ['ms']))
    specs.push(this.makeSpec('back', 'Go back in history', [], []))
    specs.push(this.makeSpec('forward', 'Go forward in history', [], []))
    return specs
  }

  private getSystemPrompt(): string {
    return 'You are a browser automation agent. You control a webview through tools. ' +
      'Use navigate to open pages, getText to read content, click/type/scroll to interact. ' +
      'Complete the user task step by step. When the task is done, reply with the final answer as plain text WITHOUT calling any tool.'
  }

  /** P2 核心任务执行循环 */
  async runAgentTask(agentId: string): Promise<void> {
    const config = this.agents.get(agentId)
    if (!config) {
      console.error('[AgentEngine] runAgentTask: agent not found ' + agentId)
      return
    }
    if (this.runningTasks.has(agentId)) {
      console.info('[AgentEngine] task already running: ' + agentId)
      return
    }
    this.runningTasks.add(agentId)

    const cfg = ConfigManager.get()
    if (!cfg.llmBaseUrl || cfg.llmBaseUrl.length === 0) {
      this.setAgentError(agentId, 'LLM 未配置：请先在设置中填写 API 端点')
      this.setAgentActivity(agentId, 'LLM 未配置：请先在设置中填写 API 端点')
      console.error('[AgentEngine] LLM not configured, agent aborted: ' + agentId)
      this.finalAnswers.set(agentId, 'LLM 未配置：请先在设置中填写 API 端点')
      this.runningTasks.delete(agentId)
      return
    }

    console.info(`[AgentEngine] task start: ${agentId} desc="${config.taskDescription}" baseUrl=${cfg.llmBaseUrl} model=${cfg.llmModel}`)
    this.setAgentRunning(agentId)
    this.updateAgentProgress(agentId, 0)

    // P4: start session recording
    const session = SessionManager.startRecording(agentId, config.tabId)
    if (session) {
      this.agentSessions.set(agentId, session.sessionId)
    }

    // P5: 等待该 agent 的 tab 的 Web 组件挂载（BrowserShell 多 Web 常驻架构下
    // 创建 tab 即挂载；若 BrowserShell 尚未渲染（覆盖态），轮询等待用户回到前台）
    let bound = false
    for (let wait = 0; wait < 20; wait++) {
      const instance = TabManager.getWebView(config.tabId)
      if (instance !== null && instance !== undefined && instance.controller) {
        BCPEngine.bindWebView(instance.controller, config.tabId)
        bound = true
        console.info('[AgentEngine] BCPEngine bound to tab ' + config.tabId + ' after ' + wait + ' polls')
        break
      }
      if (wait === 0) {
        console.info('[AgentEngine] waiting for webview on tab ' + config.tabId + ' (agent tab not rendered yet)')
      }
      await new Promise<void>((resolve) => { setTimeout(() => { resolve() }, 500) })
    }
    if (!bound) {
      console.warn('[AgentEngine] WebView not registered for tab ' + config.tabId + ' after 10s, agent tools will fail')
    } else {
      // P24a: 绑定成功即点亮页面辉光(运行中视觉指示)
      this.__glowStart(agentId)
      if (config.targetUrl && config.targetUrl.length > 0) {
      // P6: agent tab 创建即自动导航到目标页（Web 层常驻架构，前台后台均生效），
      // 消灭「依赖人工点击 tab 触发渲染」的时序缺口
      try {
        BCPEngine.navigate(config.targetUrl)
        console.info('[AgentEngine] auto-navigate agent tab to target: ' + config.targetUrl)
      } catch (e) {
        console.warn('[AgentEngine] auto-navigate failed: ' + e)
      }
      }
    }

    const messages: LLMChatMessage[] = []
    messages.push(LLMChatMessage.system(this.getSystemPrompt()))
    const userPrompt = config.taskDescription
      + (config.targetUrl ? ` (target page: ${config.targetUrl})` : '')
    messages.push(LLMChatMessage.user(userPrompt))

    const tools = this.getToolSpecs()
    let finalAnswer = ''
    let failed = false
    let failReason = ''

    try {
      for (let step = 1; step <= AgentEngineImpl.MAX_STEPS; step++) {
        // P24a: 页面停止钮轮询——标记即终止(镜像 terminateAgent 清理链)
        if (await this.__glowStopRequested(agentId)) {
          console.info('[AgentEngine] stop requested via page glow button: ' + agentId)
          this.terminateAgent(agentId)
          this.runningTasks.delete(agentId)
          this.finalAnswers.set(agentId, '任务已通过页面停止钮终止')
          const sid0 = this.agentSessions.get(agentId)
          if (sid0) {
            SessionManager.stopRecording(sid0)
          }
          return
        }
        console.info(`[AgentEngine] step ${step}/${AgentEngineImpl.MAX_STEPS} agent=${agentId}`)
        this.updateAgentProgress(agentId, Math.round((step - 1) * 100 / AgentEngineImpl.MAX_STEPS))

        // P12a: 优先 SSE 流式（onDelta 实时更新磁贴/侧栏活动文本），失败降级非流式重试一次
        let response = await LLMClient.chatStream({
          baseUrl: cfg.llmBaseUrl,
          apiKey: cfg.llmApiKey,
          model: cfg.llmModel,
          messages: messages,
          tools: tools,
          timeoutMs: AgentEngineImpl.LLM_TIMEOUT_MS
        }, (partial: string, total: string) => {
          const tail = total.length > 48 ? total.substring(total.length - 48) : total
          this.agentActivities.set(agentId, `思考中: ${tail}`)
        })
        if (response === null) {
          console.warn('[AgentEngine] stream failed (' + LLMClient.lastError + '), fallback to non-stream chat')
          response = await LLMClient.chat({
            baseUrl: cfg.llmBaseUrl,
            apiKey: cfg.llmApiKey,
            model: cfg.llmModel,
            messages: messages,
            tools: tools,
            timeoutMs: AgentEngineImpl.LLM_TIMEOUT_MS
          })
        }

        if (!response) {
          failed = true
          failReason = 'LLM 请求失败：请检查 API 端点与网络'
          break
        }

        if (response === null || response === undefined) {
          failed = true
          failReason = 'LLM 响应为空'
          break
        }

        if (response.hasToolCalls) {
          messages.push(LLMChatMessage.assistant(response.content.length > 0 ? response.content : null, response.tool_calls))
          for (const call of response.tool_calls) {
            const activitySummary = this.summarizeToolCall(call)
            console.info(`[AgentEngine] tool_call: ${call.function_name} ${call.function_args} (id=${call.id})`)
            this.setAgentActivity(agentId, activitySummary)
            const result = await this.executeToolCall(agentId, call)
            const resultText = this.formatBCPResult(result)
            console.info(`[AgentEngine] tool_result: ${call.function_name} -> ${resultText.substring(0, 200)}`)
            messages.push(LLMChatMessage.toolResult(call.id, resultText))

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
            }
            const tab = TabManager.getTab(config.tabId)
            if (tab !== null && tab !== undefined && tab.currentUrl) {
              this.updateAgentProgress(agentId, Math.round(step * 100 / AgentEngineImpl.MAX_STEPS), tab.currentUrl)
            }
          }
          continue
        }

        // 纯 content：任务完成
        finalAnswer = response.content
        console.info(`[AgentEngine] task complete, answer: ${finalAnswer.substring(0, 300)}`)
        break
      }

      if (!failed && finalAnswer.length === 0 && !this.receivedAnswer(messages)) {
        // 步数耗尽
        failed = true
        failReason = `达到最大步数 (${AgentEngineImpl.MAX_STEPS})`
      }
    } catch (e) {
      failed = true
      failReason = `执行异常: ${e}`
    } finally {
      this.runningTasks.delete(agentId)
    }

    if (failed) {
      console.error(`[AgentEngine] task failed: ${agentId} reason=${failReason}`)
      this.setAgentError(agentId, failReason)
      this.setAgentActivity(agentId, '失败: ' + failReason)
      this.finalAnswers.set(agentId, '任务失败: ' + failReason)
    } else {
      this.setAgentActivity(agentId, '完成: ' + finalAnswer.substring(0, 80))
      this.setAgentCompleted(agentId)
      this.finalAnswers.set(agentId, finalAnswer.length > 0 ? finalAnswer : '(空答复)')
    }

    // P24a: 终态(完成/失败/停止)移除页面辉光
    this.__glowStop(agentId)

    // P4: stop recording and persist (keep agentId->sessionId mapping for replay entry)
    const sid2 = this.agentSessions.get(agentId)
    if (sid2) {
      SessionManager.stopRecording(sid2)
    }
  }

  private receivedAnswer(messages: LLMChatMessage[]): boolean {
    if (messages.length === 0) {
      return false
    }
    return false
  }

  private summarizeToolCall(call: LLMToolCall): string {
    const name = call.function_name
    let argsPreview = call.function_args
    if (argsPreview.length > 60) {
      argsPreview = argsPreview.substring(0, 60) + '...'
    }
    return `${name}(${argsPreview})`
  }

  private formatBCPResult(result: BCPResult): string {
    const obj = new BCPResultJSON()
    obj.success = result.success
    obj.data = result.data === null ? '' : (result.data.length > 4000 ? result.data.substring(0, 4000) : result.data)
    obj.error = result.error === null ? '' : result.error
    return JSON.stringify(obj)
  }

  private bcpFail(errorMsg: string): BCPResult {
    const r = new BCPResultImpl()
    r.success = false
    r.data = null
    r.error = errorMsg
    return r
  }

  private bcpDone(data: string): BCPResult {
    const r = new BCPResultImpl()
    r.success = true
    r.data = data
    r.error = null
    return r
  }

  private argStr(args: Record<string, Object>, key: string): string {
    const v = args[key]
    return v === undefined || v === null ? '' : `${v}`
  }

  private argNum(args: Record<string, Object>, key: string, dflt: number): number {
    const v = args[key]
    if (v === undefined || v === null) {
      return dflt
    }
    const n = Number(v)
    return Number.isNaN(n) ? dflt : n
  }

  /** 经 BCPEngine 执行单个工具调用；click 前经敏感操作检测 */
  private async executeToolCall(agentId: string, call: LLMToolCall): Promise<BCPResult> {
    let args: Record<string, Object> = {}
    try {
      args = JSON.parse(call.function_args) as Record<string, Object>
    } catch (e) {
      return this.bcpFail(`invalid tool args: ${call.function_args}`)
    }
    const name = call.function_name
    try {
      if (name === 'navigate') {
        const url = this.argStr(args, 'url')
        if (!url) {
          return this.bcpFail('missing url')
        }
        const sensitive = SensitiveOperationDetector.detectNavigation(agentId, url)
        if (sensitive) {
          // P6: 敏感导航走用户确认链（ConfirmDialog → Promise resolve），不再静默拦截
          console.info('[AgentEngine] sensitive navigate -> requestConfirmation: ' + sensitive + ' url=' + url)
          const confirmed = await SensitiveOperationDetector.requestConfirmation(agentId, sensitive, url, '')
          console.info('[AgentEngine] requestConfirmation resolved: ' + confirmed)
          if (!confirmed) {
            return this.bcpFail(`sensitive navigation rejected by user: ${sensitive}`)
          }
        }
        return await BCPEngine.navigate(url)
      }
      if (name === 'click') {
        const selector = this.argStr(args, 'selector')
        const sensitive = SensitiveOperationDetector.detectClick(agentId, selector, '')
        if (sensitive) {
          // P6: 敏感点击走确认链
          console.info('[AgentEngine] sensitive click -> requestConfirmation: ' + sensitive + ' selector=' + selector)
          const confirmed = await SensitiveOperationDetector.requestConfirmation(agentId, sensitive, '', selector)
          console.info('[AgentEngine] requestConfirmation resolved: ' + confirmed)
          if (!confirmed) {
            return this.bcpFail(`sensitive click rejected by user: ${sensitive}`)
          }
        }
        return await BCPEngine.click(selector)
      }
      if (name === 'type') {
        const selector = this.argStr(args, 'selector')
        const text = this.argStr(args, 'text')
        return await BCPEngine.type(selector, text)
      }
      if (name === 'getText') {
        return await BCPEngine.getText()
      }
      if (name === 'snapshot') {
        return await BCPEngine.snapshotMarkdown()
      }
      if (name === 'scroll') {
        const dx = this.argNum(args, 'deltaX', 0)
        const dy = this.argNum(args, 'deltaY', 0)
        return await BCPEngine.scroll(dx, dy)
      }
      if (name === 'wait') {
        const ms = Math.min(this.argNum(args, 'ms', 1000), 10000)
        return await BCPEngine.wait(ms)
      }
      if (name === 'back') {
        return await BCPEngine.back()
      }
      if (name === 'forward') {
        return await BCPEngine.forward()
      }
      return this.bcpFail(`unknown tool: ${name}`)
    } catch (e) {
      return this.bcpFail(`tool exec error: ${e}`)
    }
  }

  terminateAll(): void {
    for (const agentId of Array.from(this.agents.keys())) {
      this.terminateAgent(agentId)
    }
  }
}

export const AgentEngine = new AgentEngineImpl()