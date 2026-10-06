# -*- coding: utf-8 -*-
"""P2 patch part 4: AgentEngine tool specs -> typed classes; formatBCPResult typed."""
import io, sys

def patch(path, replacements):
    with io.open(path, 'r', encoding='utf-8', newline=None) as f:
        t = f.read()
    for old, new in replacements:
        if old not in t:
            print('MISS: %r not found in %s' % (old[:80], path)); sys.exit(1)
        if t.count(old) != 1:
            print('DUP: %r appears %d times in %s' % (old[:80], t.count(old), path)); sys.exit(1)
        t = t.replace(old, new)
    with io.open(path, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write(t)
    print('OK', path)

AE = r'D:\BrowserOS - KaihongOS\entry\src\main\ets\service\AgentEngine.ets'
patch(AE, [
    # import 补 LLMParamProp/LLMParamsSchema
    ("""import { LLMClient, LLMChatMessage, LLMToolCall, LLMToolSpec } from './LLMClient'""",
     """import { LLMClient, LLMChatMessage, LLMToolCall, LLMToolSpec, LLMParamProp, LLMParamsSchema } from './LLMClient'"""),
    # 整个 getToolSpecs 换成类型化版本
    ("""  /** BCP 工具表（JSON Schema），与 BCPEngine 方法一一对应 */
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
  }""",
     """  /** 单工具 schema 构造辅助 */
  private makeSpec(name: string, description: string, props: Record<string, LLMParamProp>, required: string[]): LLMToolSpec {
    const params = new LLMParamsSchema()
    params.properties = props
    params.required = required.length > 0 ? required : null
    const spec: LLMToolSpec = { name: name, description: description, parameters: params }
    return spec
  }

  private strProp(desc: string): LLMParamProp {
    return new LLMParamProp('string', desc)
  }

  private numProp(desc: string): LLMParamProp {
    return new LLMParamProp('number', desc)
  }

  /** BCP 工具表（JSON Schema），与 BCPEngine 方法一一对应 */
  getToolSpecs(): LLMToolSpec[] {
    const specs: LLMToolSpec[] = []
    const navProps: Record<string, LLMParamProp> = { url: this.strProp('The URL to navigate to') }
    specs.push(this.makeSpec('navigate', 'Navigate the webview to a URL', navProps, ['url']))
    const clickProps: Record<string, LLMParamProp> = { selector: this.strProp('CSS selector of the element') }
    specs.push(this.makeSpec('click', 'Click an element by CSS selector', clickProps, ['selector']))
    const typeProps: Record<string, LLMParamProp> = {
      selector: this.strProp('CSS selector of the input element'),
      text: this.strProp('Text to type')
    }
    specs.push(this.makeSpec('type', 'Type text into an element', typeProps, ['selector', 'text']))
    specs.push(this.makeSpec('getText', 'Get visible text of the current page', {}, []))
    specs.push(this.makeSpec('snapshot', 'Get DOM snapshot info of the current page', {}, []))
    const scrollProps: Record<string, LLMParamProp> = {
      deltaX: this.numProp('Horizontal scroll pixels'),
      deltaY: this.numProp('Vertical scroll pixels')
    }
    specs.push(this.makeSpec('scroll', 'Scroll the page', scrollProps, ['deltaY']))
    const waitProps: Record<string, LLMParamProp> = { ms: this.numProp('Milliseconds to wait, max 10000') }
    specs.push(this.makeSpec('wait', 'Wait for milliseconds', waitProps, ['ms']))
    specs.push(this.makeSpec('back', 'Go back in history', {}, []))
    specs.push(this.makeSpec('forward', 'Go forward in history', {}, []))
    return specs
  }"""),
    # formatBCPResult typed
    ("""  private formatBCPResult(result: BCPResult): string {
    const obj: Record<string, Object> = {
      success: result.success,
      data: result.data === null ? '' : (result.data.length > 4000 ? result.data.substring(0, 4000) : result.data),
      error: result.error === null ? '' : result.error
    }
    return JSON.stringify(obj)
  }""",
     """  private formatBCPResult(result: BCPResult): string {
    const obj = new BCPResultJSON()
    obj.success = result.success
    obj.data = result.data === null ? '' : (result.data.length > 4000 ? result.data.substring(0, 4000) : result.data)
    obj.error = result.error === null ? '' : result.error
    return JSON.stringify(obj)
  }"""),
    # 补 BCPResultJSON 类（放在 AgentTimeoutErrorData 接口后）
    ("""interface AgentTimeoutErrorData {
  code: string
  message: string
  agentId: string
}""",
     """interface AgentTimeoutErrorData {
  code: string
  message: string
  agentId: string
}

/** BCPResult 的 JSON 序列化形（ArkTS 严格模式：字面量需显式类） */
class BCPResultJSON {
  success: boolean = false
  data: string = ''
  error: string = ''
}"""),
])
print('AGENT ENGINE TYPED OK')
