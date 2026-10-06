# -*- coding: utf-8 -*-
"""P2 patch part 2: AgentEngine task loop."""
import io, sys

def patch(path, replacements):
    with io.open(path, 'r', encoding='utf-8', newline=None) as f:
        t = f.read()
    for old, new in replacements:
        if old not in t:
            print('MISS: %r not found in %s' % (old[:60], path)); sys.exit(1)
        if t.count(old) != 1:
            print('DUP: %r appears %d times in %s' % (old[:60], t.count(old), path)); sys.exit(1)
        t = t.replace(old, new)
    with io.open(path, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(t)
    print('OK', path)

AE = r'D:\BrowserOS - KaihongOS\entry\src\main\ets\service\AgentEngine.ets'

# 1) imports
patch(AE, [
    ("""import { ConfigManager } from '../storage/ConfigManager'""",
     """import { ConfigManager } from '../storage/ConfigManager'
import { LLMClient, LLMChatMessage, LLMToolCall, LLMToolSpec } from './LLMClient'
import { BCPEngine } from '../protocol/BCPEngine'
import { SensitiveOperationDetector } from './SensitiveOperationDetector'
import { BCPResult } from '../common/Types'"""),
])

# 2) class fields + activity map
patch(AE, [
    ("""  private heartbeatTimers: Map<string, number> = new Map()
  private timeoutTimers: Map<string, number> = new Map()""",
     """  private heartbeatTimers: Map<string, number> = new Map()
  private timeoutTimers: Map<string, number> = new Map()
  private agentActivities: Map<string, string> = new Map()
  private runningTasks: Set<string> = new Set()
  private static readonly MAX_STEPS: number = 15
  private static readonly LLM_TIMEOUT_MS: number = 30000"""),
])

# 3) createAgent: auto-start
patch(AE, [
    ("""    EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())

    this.startHeartbeat(agentId)

    return config
  }""",
     """    EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())

    this.startHeartbeat(agentId)

    // P2: 配置齐全则自动开跑（异步，不阻塞 UI）
    const cfg = ConfigManager.get()
    if (cfg.llmBaseUrl && cfg.llmBaseUrl.length > 0) {
      this.runAgentTask(agentId)
    } else {
      console.info('[AgentEngine] LLM not configured, agent stays idle: ' + agentId)
    }

    return config
  }"""),
])

# 4) runAgentTask 主循环 + 工具表 + 执行器 —— 追加在 terminateAll 之前
patch(AE, [
    ("""  terminateAll(): void {""",
     """  getAgentActivity(agentId: string): string {
    return this.agentActivities.get(agentId) || ''
  }

  private setAgentActivity(agentId: string, activity: string): void {
    this.agentActivities.set(agentId, activity)
    const status = this.agentStatuses.get(agentId)
    if (status) {
      EventBus.emit(EventBusEvents.AGENT_HEARTBEAT, status.toJSON())
    }
  }

  /** BCP 工具表（JSON Schema），与 BCPEngine 方法一一对应 */
  getToolSpecs(): LLMToolSpec[] {
    const specs: LLMToolSpec[] = []
    specs.push({
      name: 'navigate',
      description: 'Navigate the webview to a URL',
      parameters: {
        type: 'object',
        properties: {
          url: { type: 'string', description: 'The URL to navigate to' }
        },
        required: ['url']
      } as Record<string, Object>
    })
    specs.push({
      name: 'click',
      description: 'Click an element by CSS selector',
      parameters: {
        type: 'object',
        properties: {
          selector: { type: 'string', description: 'CSS selector of the element' }
        },
        required: ['selector']
      } as Record<string, Object>
    })
    specs.push({
      name: 'type',
      description: 'Type text into an element',
      parameters: {
        type: 'object',
        properties: {
          selector: { type: 'string', description: 'CSS selector of the input element' },
          text: { type: 'string', description: 'Text to type' }
        },
        required: ['selector', 'text']
      } as Record<string, Object>
    })
    specs.push({
      name: 'getText',
      description: 'Get visible text of the current page',
      parameters: {
        type: 'object',
        properties: {}
      } as Record<string, Object>
    })
    specs.push({
      name: 'snapshot',
      description: 'Get DOM snapshot info of the current page',
      parameters: {
        type: 'object',
        properties: {}
      } as Record<string, Object>
    })
    specs.push({
      name: 'scroll',
      description: 'Scroll the page',
      parameters: {
        type: 'object',
        properties: {
          deltaX: { type: 'number', description: 'Horizontal scroll pixels' },
          deltaY: { type: 'number', description: 'Vertical scroll pixels' }
        },
        required: ['deltaY']
      } as Record<string, Object>
    })
    specs.push({
      name: 'wait',
      description: 'Wait for milliseconds',
      parameters: {
        type: 'object',
        properties: {
          ms: { type: 'number', description: 'Milliseconds to wait, max 10000' }
        },
        required: ['ms']
      } as Record<string, Object>
    })
    specs.push({
      name: 'back',
      description: 'Go back in history',
      parameters: {
        type: 'object',
        properties: {}
      } as Record<string, Object>
    })
    specs.push({
      name: 'forward',
      description: 'Go forward in history',
      parameters: {
        type: 'object',
        properties: {}
      } as Record<string, Object>
    })
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
      this.runningTasks.delete(agentId)
      return
    }

    console.info(`[AgentEngine] task start: ${agentId} desc="${config.taskDescription}" baseUrl=${cfg.llmBaseUrl} model=${cfg.llmModel}`)
    this.setAgentRunning(agentId)
    this.updateAgentProgress(agentId, 0)

    // 绑定该 agent 的 tab 的 WebViewAdapter
    const instance = TabManager.getWebView(config.tabId)
    if (instance) {
      BCPEngine.bindWebView(instance.controller, config.tabId)
      console.info('[AgentEngine] BCPEngine bound to tab ' + config.tabId)
    } else {
      console.warn('[AgentEngine] WebView not registered for tab ' + config.tabId + ' (agents page runs headless until tab opened)')
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
        console.info(`[AgentEngine] step ${step}/${AgentEngineImpl.MAX_STEPS} agent=${agentId}`)
        this.updateAgentProgress(agentId, Math.round((step - 1) * 100 / AgentEngineImpl.MAX_STEPS))

        const response = await LLMClient.chat({
          baseUrl: cfg.llmBaseUrl,
          apiKey: cfg.llmApiKey,
          model: cfg.llmModel,
          messages: messages,
          tools: tools,
          timeoutMs: AgentEngineImpl.LLM_TIMEOUT_MS
        })

        if (!response) {
          failed = true
          failReason = 'LLM 请求失败：请检查 API 端点与网络'
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
            const tab = TabManager.getTab(config.tabId)
            if (tab && tab.currentUrl) {
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
    } else {
      this.setAgentActivity(agentId, '完成: ' + finalAnswer.substring(0, 80))
      this.setAgentCompleted(agentId)
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
    const obj: Record<string, Object> = {
      success: result.success,
      data: result.data === null ? '' : (result.data.length > 4000 ? result.data.substring(0, 4000) : result.data),
      error: result.error === null ? '' : result.error
    }
    return JSON.stringify(obj)
  }

  /** 经 BCPEngine 执行单个工具调用；click 前经敏感操作检测 */
  private async executeToolCall(agentId: string, call: LLMToolCall): Promise<BCPResult> {
    let args: Record<string, Object> = {}
    try {
      args = JSON.parse(call.function_args) as Record<string, Object>
    } catch (e) {
      return { success: false, data: null, error: `invalid tool args: ${call.function_args}` }
    }
    const name = call.function_name
    try {
      if (name === 'navigate') {
        const url = `${args['url'] || ''}`
        if (!url) {
          return { success: false, data: null, error: 'missing url' }
        }
        const sensitive = SensitiveOperationDetector.detectNavigation(agentId, url)
        if (sensitive) {
          return { success: false, data: null, error: `sensitive navigation blocked: ${sensitive}` }
        }
        return await BCPEngine.navigate(url)
      }
      if (name === 'click') {
        const selector = `${args['selector'] || ''}`
        const sensitive = SensitiveOperationDetector.detectClick(agentId, selector, '')
        if (sensitive) {
          return { success: false, data: null, error: `sensitive click blocked: ${sensitive}` }
        }
        return await BCPEngine.click(selector)
      }
      if (name === 'type') {
        const selector = `${args['selector'] || ''}`
        const text = `${args['text'] || ''}`
        return await BCPEngine.type(selector, text)
      }
      if (name === 'getText') {
        return await BCPEngine.getText()
      }
      if (name === 'snapshot') {
        return await BCPEngine.snapshot()
      }
      if (name === 'scroll') {
        const dx = Number(args['deltaX'] || 0)
        const dy = Number(args['deltaY'] || 0)
        return await BCPEngine.scroll(dx, dy)
      }
      if (name === 'wait') {
        const ms = Math.min(Number(args['ms'] || 1000), 10000)
        return await BCPEngine.wait(ms)
      }
      if (name === 'back') {
        return await BCPEngine.back()
      }
      if (name === 'forward') {
        return await BCPEngine.forward()
      }
      return { success: false, data: null, error: `unknown tool: ${name}` }
    } catch (e) {
      return { success: false, data: null, error: `tool exec error: ${e}` }
    }
  }

  terminateAll(): void {"""),
])

# 5) resetAgent 清 activity
patch(AE, [
    ("""    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.IDLE)
      status.currentUrl = ''
      status.progress = 0
      status.errorMessage = ''
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.IDLE)
    }

    return true
  }""",
     """    const status = this.agentStatuses.get(agentId)
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
  }"""),
])

print('AGENT ENGINE PATCHED')
