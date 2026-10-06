# -*- coding: utf-8 -*-
"""P2 patch part 6: fix brace + BCPResult typed returns + response null-guard."""
import io, sys

def patch(path, replacements):
    with io.open(path, 'r', encoding='utf-8', newline=None) as f:
        t = f.read()
    for old, new in replacements:
        if old not in t:
            print('MISS: %r' % old[:80]); sys.exit(1)
        if t.count(old) != 1:
            print('DUP: %d' % t.count(old)); sys.exit(1)
        t = t.replace(old, new)
    with io.open(path, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(t)
    print('OK', path)

AE = r'D:\BrowserOS - KaihongOS\entry\src\main\ets\service\AgentEngine.ets'
patch(AE, [
    # 1) 双大括号修复
    ("""  private emptyProps(): Record<string, LLMParamProp> {
    return this.toProps(new Map<string, LLMParamProp>())
  }
  }""",
     """  private emptyProps(): Record<string, LLMParamProp> {
    return this.toProps(new Map<string, LLMParamProp>())
  }"""),
    # 2) executeToolCall 里的无类型 BCPResult 字面量 -> 显式类 + 辅助方法
    ("""  /** 经 BCPEngine 执行单个工具调用；click 前经敏感操作检测 */
  private async executeToolCall(agentId: string, call: LLMToolCall): Promise<BCPResult> {
    let args: Record<string, Object> = {}
    try {
      args = JSON.parse(call.function_args) as Record<string, Object>
    } catch (e) {
      return { success: false, data: null, error: `invalid tool args: ${call.function_args}` }
    }""",
     """  private bcpFail(errorMsg: string): BCPResult {
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
    }"""),
    # 3) 函数体内所有 return { success: ... } 换成辅助
    ("""      if (name === 'navigate') {
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
      }""",
     """      if (name === 'navigate') {
        const url = this.argStr(args, 'url')
        if (!url) {
          return this.bcpFail('missing url')
        }
        const sensitive = SensitiveOperationDetector.detectNavigation(agentId, url)
        if (sensitive) {
          return this.bcpFail(`sensitive navigation blocked: ${sensitive}`)
        }
        return await BCPEngine.navigate(url)
      }
      if (name === 'click') {
        const selector = this.argStr(args, 'selector')
        const sensitive = SensitiveOperationDetector.detectClick(agentId, selector, '')
        if (sensitive) {
          return this.bcpFail(`sensitive click blocked: ${sensitive}`)
        }
        return await BCPEngine.click(selector)
      }
      if (name === 'type') {
        const selector = this.argStr(args, 'selector')
        const text = this.argStr(args, 'text')
        return await BCPEngine.type(selector, text)
      }"""),
    ("""      if (name === 'scroll') {
        const dx = Number(args['deltaX'] || 0)
        const dy = Number(args['deltaY'] || 0)
        return await BCPEngine.scroll(dx, dy)
      }
      if (name === 'wait') {
        const ms = Math.min(Number(args['ms'] || 1000), 10000)
        return await BCPEngine.wait(ms)
      }""",
     """      if (name === 'scroll') {
        const dx = this.argNum(args, 'deltaX', 0)
        const dy = this.argNum(args, 'deltaY', 0)
        return await BCPEngine.scroll(dx, dy)
      }
      if (name === 'wait') {
        const ms = Math.min(this.argNum(args, 'ms', 1000), 10000)
        return await BCPEngine.wait(ms)
      }"""),
    ("""      return { success: false, data: null, error: `unknown tool: ${name}` }
    } catch (e) {
      return { success: false, data: null, error: `tool exec error: ${e}` }
    }
  }""",
     """      return this.bcpFail(`unknown tool: ${name}`)
    } catch (e) {
      return this.bcpFail(`tool exec error: ${e}`)
    }
  }"""),
    # 4) BCPResultImpl 类
    ("""/** BCPResult 的 JSON 序列化形（ArkTS 严格模式：字面量需显式类） */
class BCPResultJSON {
  success: boolean = false
  data: string = ''
  error: string = ''
}""",
     """/** BCPResult 的 JSON 序列化形（ArkTS 严格模式：字面量需显式类） */
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
}"""),
    # 5) runAgentTask 里 response null guard（拆 if）
    ("""        if (!response) {
          failed = true
          failReason = 'LLM 请求失败：请检查 API 端点与网络'
          break
        }

        if (response.hasToolCalls) {""",
     """        if (!response) {
          failed = true
          failReason = 'LLM 请求失败：请检查 API 端点与网络'
          break
        }

        if (response === null || response === undefined) {
          failed = true
          failReason = 'LLM 响应为空'
          break
        }

        if (response.hasToolCalls) {"""),
    # 6) instance null guard
    ("""    // 绑定该 agent 的 tab 的 WebViewAdapter
    const instance = TabManager.getWebView(config.tabId)
    if (instance) {
      BCPEngine.bindWebView(instance.controller, config.tabId)
      console.info('[AgentEngine] BCPEngine bound to tab ' + config.tabId)
    } else {
      console.warn('[AgentEngine] WebView not registered for tab ' + config.tabId + ' (agents page runs headless until tab opened)')
    }""",
     """    // 绑定该 agent 的 tab 的 WebViewAdapter
    const instance = TabManager.getWebView(config.tabId)
    if (instance !== null && instance !== undefined && instance.controller) {
      BCPEngine.bindWebView(instance.controller, config.tabId)
      console.info('[AgentEngine] BCPEngine bound to tab ' + config.tabId)
    } else {
      console.warn('[AgentEngine] WebView not registered for tab ' + config.tabId + ' (agent tools will fail until tab opened)')
    }"""),
    # 7) tab null guard in loop
    ("""            messages.push(LLMChatMessage.toolResult(call.id, resultText))
            const tab = TabManager.getTab(config.tabId)
            if (tab && tab.currentUrl) {
              this.updateAgentProgress(agentId, Math.round(step * 100 / AgentEngineImpl.MAX_STEPS), tab.currentUrl)
            }""",
     """            messages.push(LLMChatMessage.toolResult(call.id, resultText))
            const tab = TabManager.getTab(config.tabId)
            if (tab !== null && tab !== undefined && tab.currentUrl) {
              this.updateAgentProgress(agentId, Math.round(step * 100 / AgentEngineImpl.MAX_STEPS), tab.currentUrl)
            }"""),
])
print('FIX6 OK')
