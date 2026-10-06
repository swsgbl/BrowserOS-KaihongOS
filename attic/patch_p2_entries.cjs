# -*- coding: utf-8 -*-
"""P2 patch part 7: getToolSpecs entries-based (no Record literals)."""
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
    ("""import { LLMClient, LLMChatMessage, LLMToolCall, LLMToolSpec, LLMParamProp, LLMParamsSchema } from './LLMClient'""",
     """import { LLMClient, LLMChatMessage, LLMToolCall, LLMToolSpec, LLMParamProp, LLMParamEntry, LLMParamsSchema } from './LLMClient'"""),
    # 替换 makeSpec/toProps/emptyProps + getToolSpecs 整段
    ("""  /** 单工具 schema 构造辅助 */
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
  }""",
     """  /** 单工具 schema 构造辅助（entries 数组，规避 Record 字面量） */
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
  }"""),
    ("""  getToolSpecs(): LLMToolSpec[] {
    const specs: LLMToolSpec[] = []
    const navProps: Record<string, LLMParamProp> = new Map<string, LLMParamProp>()
    navProps.set('url', this.strProp('The URL to navigate to'))
    specs.push(this.makeSpec('navigate', 'Navigate the webview to a URL', this.toProps(navProps), ['url']))
    const clickProps: Record<string, LLMParamProp> = new Map<string, LLMParamProp>()
    clickProps.set('selector', this.strProp('CSS selector of the element'))
    specs.push(this.makeSpec('click', 'Click an element by CSS selector', this.toProps(clickProps), ['selector']))
    const typeProps: Record<string, LLMParamProp> = new Map<string, LLMParamProp>()
    typeProps.set('selector', this.strProp('CSS selector of the input element'))
    typeProps.set('text', this.strProp('Text to type'))
    specs.push(this.makeSpec('type', 'Type text into an element', this.toProps(typeProps), ['selector', 'text']))
    specs.push(this.makeSpec('getText', 'Get visible text of the current page', this.emptyProps(), []))
    specs.push(this.makeSpec('snapshot', 'Get DOM snapshot info of the current page', this.emptyProps(), []))
    const scrollProps: Record<string, LLMParamProp> = new Map<string, LLMParamProp>()
    scrollProps.set('deltaX', this.numProp('Horizontal scroll pixels'))
    scrollProps.set('deltaY', this.numProp('Vertical scroll pixels'))
    specs.push(this.makeSpec('scroll', 'Scroll the page', this.toProps(scrollProps), ['deltaY']))
    const waitProps: Record<string, LLMParamProp> = new Map<string, LLMParamProp>()
    waitProps.set('ms', this.numProp('Milliseconds to wait, max 10000'))
    specs.push(this.makeSpec('wait', 'Wait for milliseconds', this.toProps(waitProps), ['ms']))
    specs.push(this.makeSpec('back', 'Go back in history', this.emptyProps(), []))
    specs.push(this.makeSpec('forward', 'Go forward in history', this.emptyProps(), []))
    return specs
  }

  private toProps(m: Map<string, LLMParamProp>): Record<string, LLMParamProp> {
    const r: Record<string, LLMParamProp> = {}
    m.forEach((v, k) => {
      r[k] = v
    })
    return r
  }

  private emptyProps(): Record<string, LLMParamProp> {
    return this.toProps(new Map<string, LLMParamProp>())
  }""",
     """  getToolSpecs(): LLMToolSpec[] {
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
    specs.push(this.makeSpec('snapshot', 'Get DOM snapshot info of the current page', [], []))
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
  }"""),
])
print('ENTRIES OK')
