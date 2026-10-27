// P51 fix: BCPEngine bridge-injection race after rebind (fresh bind -> runJavaScript inject is async;
// immediately following executeJS may run before the bridge functions exist -> null).
const fs = require('fs')
const FILE = 'entry/src/main/ets/protocol/BCPEngine.ets'
let s = fs.readFileSync(FILE, 'utf8')
const D = s.includes('\r\n') ? '\r\n' : '\n'
function rep(o, n, tag) {
  const oo = o.split('\n').join(D), nn = n.split('\n').join(D)
  if (s.includes(nn)) { console.log('skip: ' + tag); return }
  if (!s.includes(oo)) { console.error('MISS: ' + tag); process.exit(1) }
  s = s.replace(oo, nn)
  console.log('ok: ' + tag)
}

rep(`  bindWebView(webviewController: IWebviewController, webviewId: string): void {
    this.webviewController = webviewController
    this.webviewId = webviewId
    this.bridgeInjected = false
  }`,
    `  private reboundAt: number = 0

  bindWebView(webviewController: IWebviewController, webviewId: string): void {
    this.webviewController = webviewController
    this.webviewId = webviewId
    this.bridgeInjected = false
    this.reboundAt = Date.now()
  }

  /** P51: rebind 后 bridge 注入是异步落地的；首个 executeJS 前留出注入窗口 */
  private async settleIfJustRebound(): Promise<void> {
    if (this.reboundAt === 0) {
      return
    }
    const elapsed = Date.now() - this.reboundAt
    if (elapsed < 500) {
      await new Promise<void>((res) => setTimeout(res, 500 - elapsed))
    }
  }`, 'bind-rebound')

// getText: settle before executeJS
rep(`    const js = \`window.__bcp_get_text(0);\`
    const result = await this.executeJS(js)`,
    `    await this.settleIfJustRebound()
    const js = \`window.__bcp_get_text(0);\`
    const result = await this.executeJS(js)`, 'gettext-settle')

// evaluate (selector reads): settle too — anchor on handleRead's evaluate path in BCPEngine.evaluate
rep(`  async evaluate(jsCode: string): Promise<BCPResult> {`,
    `  async evaluate(jsCode: string): Promise<BCPResult> {
    await this.settleIfJustRebound()`, 'evaluate-settle')

fs.writeFileSync(FILE, s, 'utf8')
console.log('done')
