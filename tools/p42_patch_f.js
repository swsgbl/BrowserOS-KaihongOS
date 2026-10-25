// P42-F: html2canvas 本地化（KAI-079）——rawfile 预加载 + eval 注入，CDN 仅作降级
const fs = require('fs')
const path = require('path')
const ROOT = 'D:/BrowserOS - KaihongOS'

function load(rel) {
  const p = path.join(ROOT, rel)
  return { p, lines: fs.readFileSync(p, 'utf8').split(/\r?\n/) }
}
function findLine(ctx, sub, hint) {
  const hits = []
  ctx.lines.forEach((l, i) => { if (l.includes(sub)) hits.push(i) })
  if (hits.length !== 1) throw new Error(`${ctx.p}: expect 1 hit "${sub}", got ${hits.length} (${hint})`)
  return hits[0]
}

// ============ JSBridgeInjector.ets ============
{
  const c = load('entry/src/main/ets/protocol/JSBridgeInjector.ets')
  // 1) import resourceManager + util
  if (!c.lines.some(l => l.includes("import { resourceManager } from '@kit.LocalizationKit'"))) {
    const i = findLine(c, "import { ErrorCodes } from '../common/ErrorCodes'", 'jsb-import')
    c.lines.splice(i + 1, 0, "import { resourceManager } from '@kit.LocalizationKit'", "import { util } from '@kit.ArkTS'")
  }
  // 2) HTML2CANVAS_LOADER 常量标记为 CDN 降级
  const iLoader = findLine(c, 'const HTML2CANVAS_LOADER = `', 'loader-const')
  c.lines[iLoader] = '// P42 (KAI-079): CDN loader 仅作 rawfile 预加载失败时的降级（断网下截图依赖本地源码）\nconst HTML2CANVAS_LOADER = `'
  // 3) 类成员 + preload 方法 + getHtml2CanvasLoader 改造
  const iCls = findLine(c, 'private currentWebView: IWebviewController | null = null', 'jsb-cls')
  const members = [
    '  /** P42: rawfile html2canvas.min.js 源码缓存（EntryAbility 启动时预加载） */',
    '  private html2canvasSource: string = \'\'',
    '',
    '  /** P42 (KAI-079): 从 rawfile 读 html2canvas.min.js 源码缓存（getRawFileContentSync since 9） */',
    '  preloadHtml2Canvas(rm: resourceManager.ResourceManager): void {',
    '    try {',
    "      const bytes: Uint8Array = rm.getRawFileContentSync('html2canvas.min.js')",
    "      const text = util.TextDecoder.create('utf-8').decodeWithStream(bytes)",
    '      if (text && text.length > 1000) {',
    '        this.html2canvasSource = text',
    "        console.info('[JSBridgeInjector] html2canvas local source preloaded: ' + text.length + ' chars')",
    '        return',
    '      }',
    "      console.error('[JSBridgeInjector] html2canvas rawfile too short: ' + (text ? text.length : 0))",
    '    } catch (e) {',
    "      console.error('[JSBridgeInjector] html2canvas rawfile preload failed, will fallback to CDN: ' + JSON.stringify(e))",
    '    }',
    '  }',
    ''
  ]
  c.lines.splice(iCls + 1, 0, ...members)
  // 4) getHtml2CanvasLoader 优先本地源码
  const iGet = findLine(c, 'getHtml2CanvasLoader(): string {', 'jsb-get')
  c.lines.splice(iGet, 1,
    '  getHtml2CanvasLoader(): string {',
    '    // P42 (KAI-079): 优先本地 rawfile 源码（eval 注入，断网可用）；预加载失败才降级 CDN loader',
    "    if (this.html2canvasSource.length > 1000) {",
    '      return this.html2canvasSource',
    '    }',
    '    return HTML2CANVAS_LOADER',
    '  }')
  // 5) injectBridge 内 runJavaScript(HTML2CANVAS_LOADER) 改走 getHtml2CanvasLoader()
  const iInj = findLine(c, 'webviewController.runJavaScript(HTML2CANVAS_LOADER)', 'jsb-inject')
  c.lines[iInj] = '      webviewController.runJavaScript(this.getHtml2CanvasLoader())'
  fs.writeFileSync(c.p, c.lines.join('\n'), 'utf8')
  console.log('JSBridgeInjector.ets patched')
}

// ============ EntryAbility.ets ============
{
  const c = load('entry/src/main/ets/entryability/EntryAbility.ets')
  if (!c.lines.some(l => l.includes("import { JSBridgeInjector } from '../protocol/JSBridgeInjector'"))) {
    const i = findLine(c, "import { ScheduleManager } from '../service/ScheduleManager'", 'ea-import')
    c.lines.splice(i + 1, 0, "import { JSBridgeInjector } from '../protocol/JSBridgeInjector'")
  }
  const iOn = findLine(c, 'console.info(\'BrowserOS KaihongOS EntryAbility onCreate\')', 'ea-oncreate')
  c.lines.splice(iOn + 1, 0,
    '    // P42 (KAI-079): html2canvas 本地源码预加载（rawfile → 内存缓存，截图断网可用）',
    '    JSBridgeInjector.preloadHtml2Canvas(this.context.resourceManager)')
  fs.writeFileSync(c.p, c.lines.join('\n'), 'utf8')
  console.log('EntryAbility.ets patched (F)')
}

console.log('P42-F done')
