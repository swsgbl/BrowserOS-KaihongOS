# -*- coding: utf-8 -*-
"""P2 patch part 5: Record literal -> explicit put."""
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
    ("""    const specs: LLMToolSpec[] = []
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
    return specs""",
     """    const specs: LLMToolSpec[] = []
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
  }"""),
])
print('PROPS OK')
