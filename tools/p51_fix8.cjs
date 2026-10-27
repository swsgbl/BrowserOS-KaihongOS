const fs = require('fs')
const FILE = 'entry/src/main/ets/protocol/BCPEngine.ets'
let s = fs.readFileSync(FILE, 'utf8')
const D = s.includes('\r\n') ? '\r\n' : '\n'
const o = '  bindWebView(webviewController: IWebviewController, webviewId: string): void {' + D +
  '    this.webviewController = webviewController' + D +
  '    this.webviewId = webviewId' + D +
  '    this.bridgeInjected = false' + D +
  '  }'
const n = '  private reboundAt: number = 0' + D + D +
  '  bindWebView(webviewController: IWebviewController, webviewId: string): void {' + D +
  '    this.webviewController = webviewController' + D +
  '    this.webviewId = webviewId' + D +
  '    this.bridgeInjected = false' + D +
  '    this.reboundAt = Date.now()' + D +
  '  }' + D + D +
  '  /** P51: rebind 后 bridge 注入异步落地；首个 executeJS 前留出注入窗口 */' + D +
  '  private async settleIfJustRebound(): Promise<void> {' + D +
  '    if (this.reboundAt === 0) {' + D +
  '      return' + D +
  '    }' + D +
  '    const elapsed = Date.now() - this.reboundAt' + D +
  '    if (elapsed < 500) {' + D +
  '      await new Promise<void>((res) => setTimeout(res, 500 - elapsed))' + D +
  '    }' + D +
  '  }'
if (s.includes('private reboundAt')) { console.log('skip: already'); process.exit(0) }
if (!s.includes(o)) { console.error('MISS bindWebView'); process.exit(1) }
s = s.replace(o, n)
fs.writeFileSync(FILE, s, 'utf8')
console.log('bindWebView + settleIfJustRebound added')
