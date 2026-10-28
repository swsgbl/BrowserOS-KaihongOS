import { BCPResult } from '../common/Types'
import { util } from '@kit.ArkTS'
import { IWebviewController } from '../common/IWebviewController'
import { Constants } from '../common/Constants'
import { JSBridgeInjector } from './JSBridgeInjector'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { PerformanceMonitor } from '../infra/PerformanceMonitor'

class BCPEngineImpl {
  private webviewController: IWebviewController | null = null
  private webviewId: string = ''
  private bridgeInjected: boolean = false

  private reboundAt: number = 0

  bindWebView(webviewController: IWebviewController, webviewId: string): void {
    this.webviewController = webviewController
    this.webviewId = webviewId
    this.bridgeInjected = false
    this.reboundAt = Date.now()
  }

  /** P51: rebind 后 bridge 注入异步落地；首个 executeJS 前留出注入窗口 */
  private async settleIfJustRebound(): Promise<void> {
    if (this.reboundAt === 0) {
      return
    }
    const elapsed = Date.now() - this.reboundAt
    if (elapsed < 500) {
      await new Promise<void>((res) => setTimeout(res, 500 - elapsed))
    }
  }

  unbindWebView(): void {
    this.webviewController = null
    this.webviewId = ''
    this.bridgeInjected = false
  }

  private async ensureBridge(): Promise<boolean> {
    if (!this.webviewController) {
      ErrorHandler.handle(new AppError(ErrorCodes.BCP_001, 'WebView not bound'))
      return false
    }
    if (this.bridgeInjected) {
      return true
    }
    try {
      this.webviewController.runJavaScript(JSBridgeInjector.getBridgeScript())
      this.webviewController.runJavaScript(JSBridgeInjector.getHtml2CanvasLoader())
      this.bridgeInjected = true
      JSBridgeInjector.markInjected(this.webviewId)
      return true
    } catch (e) {
      ErrorHandler.handle(new AppError(ErrorCodes.BCP_001, `Bridge injection failed: ${e}`))
      return false
    }
  }

  private async executeJS(jsCode: string, timeoutMs: number = Constants.BCP_SCRIPT_INJECT_TIMEOUT_MS): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_execute_js', 'BCP')
    try {
      if (!this.webviewController) {
        return { success: false, data: null, error: 'WebView not bound' }
      }
      // [P62-A/G] a runJavaScript promise NEVER settles if the page navigates mid-eval —
      // race it; on timeout return a loud failure instead of hanging the tool forever.
      const raced = await Promise.race([
        this.webviewController.runJavaScript(jsCode),
        new Promise<string>((res) => {
          setTimeout(() => res('__BCP_TIMEOUT__'), timeoutMs)
        })
      ])
      if (raced === '__BCP_TIMEOUT__') {
        timer()
        return { success: false, data: null, error: 'script timeout after ' + timeoutMs + 'ms (page navigating?)' }
      }
      const result = raced
      timer()
      return { success: true, data: result, error: null }
    } catch (e) {
      timer()
      return { success: false, data: null, error: `${e}` }
    }
  }

  /** [P62-G] unwrap sync-expression result: strip runJavaScript JSON quoting, parse {success,data,error} */
  private unwrapSyncJson(result: BCPResult): BCPResult {
    if (!result.success) {
      return result
    }
    let text = result.data === null || result.data === undefined ? '' : `${result.data}`
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try { text = JSON.parse(text) as string } catch (e) { }
    }
    try {
      const parsed = JSON.parse(text) as Record<string, Object>
      const ok: boolean = parsed['success'] === true
      const data: string | null = parsed['data'] === undefined || parsed['data'] === null ? null : `${parsed['data']}`
      const err: string | null = parsed['error'] === undefined || parsed['error'] === null ? null : `${parsed['error']}`
      const out: BCPResult = { success: ok, data: data, error: err }
      return out
    } catch (e) {
      return result
    }
  }

  async navigate(url: string): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_navigate', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    try {
      this.webviewController!.loadUrl(url)
      timer()
      return { success: true, data: url, error: null }
    } catch (e) {
      timer()
      return { success: false, data: null, error: `${e}` }
    }
  }

  /** P53: 当前页导出 PDF（WebviewController.createPdf, since 14）。返回 base64（大负载截断策略同 screenshot） */
  async createPdf(): Promise<BCPResult> {
    if (!this.webviewController) {
      return { success: false, data: null, error: 'WebView not bound' }
    }
    try {
      const buf = await this.webviewController.createPdf(8.27, 11.69, 0.4, true)
      const b64 = new util.Base64Helper().encodeToStringSync(buf)
      // 上限 12MB base64 —— 超限截断报错（HTTP 层另有整体限制）
      if (b64.length > 12 * 1024 * 1024) {
        return { success: false, data: null, error: 'pdf too large (>12MB base64)' }
      }
      return { success: true, data: b64, error: null }
    } catch (e) {
      return { success: false, data: null, error: `${e}` }
    }
  }

  async click(selector: string): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_click', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    // [P62-G] self-contained sync click — the old __bcp_click called __bcp_arkts_callback (a
    // registerJavaScriptProxy callback) in BOTH its try and catch paths; after navigation that proxy
    // is gone, the uncaught exception left runJavaScript's promise unsettled and callTool hung
    // unbounded (P61 90s+ hang). Same proven sync pattern; no bridge dependency.
    const js = '(function(){try{var el=document.querySelector(' + JSON.stringify(selector) + ');if(!el){return JSON.stringify({success:false,data:null,error:"Element not found: "+' + JSON.stringify(selector) + '})}el.click();return JSON.stringify({success:true,data:' + JSON.stringify(selector) + ',error:null})}catch(e){return JSON.stringify({success:false,data:null,error:String(e)})}})()'
    const result = await this.executeJS(js)
    timer()
    return this.unwrapSyncJson(result)
  }

  async type(selector: string, text: string): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_type', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    // [P62-G] sync type — same dead-proxy fix as click
    const js = '(function(){try{var el=document.querySelector(' + JSON.stringify(selector) + ');if(!el){return JSON.stringify({success:false,data:null,error:"Element not found: "+' + JSON.stringify(selector) + '})}if(el.focus){el.focus()}el.value=' + JSON.stringify(text) + ';el.dispatchEvent(new Event("input",{bubbles:true}));el.dispatchEvent(new Event("change",{bubbles:true}));return JSON.stringify({success:true,data:' + JSON.stringify(text) + ',error:null})}catch(e){return JSON.stringify({success:false,data:null,error:String(e)})}})()'
    const result = await this.executeJS(js)
    timer()
    return this.unwrapSyncJson(result)
  }

  async scroll(deltaX: number, deltaY: number): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_scroll', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    const js = `window.__bcp_scroll(${deltaX}, ${deltaY}, 0);`
    const result = await this.executeJS(js)
    timer()
    return result
  }

  async screenshot(quality: string = 'medium'): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_screenshot', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    const js = `window.__bcp_screenshot(${JSON.stringify(quality)}, 0);`
    const result = await this.executeJS(js, Constants.BCP_SCRIPT_INJECT_TIMEOUT_MS * 2)
    timer()
    return result
  }

  async snapshot(): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_snapshot', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    const js = `window.__bcp_snapshot(0);`
    const result = await this.executeJS(js)
    timer()
    return result
  }

  /** [P62-A] self-contained markdown snapshot expression — zero injected-bridge dependency.
   *  [P62-A final] Text skeleton comes from body.innerText (rendered-only: excludes style/script
   *  payloads by spec). The old clone+walk ingested a literal style-tag-source TEXT NODE on
   * baidu result pages (md = 30k chars of CSS while innerText was a clean 3k). Structure
   * (headings/links/buttons/imgs/tables) is collected via querySelectorAll + visibility filter.
   *  Returns {href,ready,md,err} JSON. */
  private buildSnapshotMdExpr(): string {
    return "(function(){try{"
      + "if(!document.body){return JSON.stringify({href:location.href,ready:document.readyState,md:'',err:'no body'})}"
      + "function vis(el){try{var cs=window.getComputedStyle(el);if(cs.display==='none'||cs.visibility==='hidden')return false}catch(e){}return true}"
      + "function txt(el){return (el.textContent||'').replace(/\\s+/g,' ').trim()}"
      + "function txtB(el,n){var t=txt(el);return t.length>n?t.substring(0,n):t}"
      + "var out=[];"
      + "var it=(document.body.innerText||'').replace(/\\n{3,}/g,String.fromCharCode(10)+String.fromCharCode(10));"
      + "if(it.length>0){out.push(it.substring(0,24000))}"
      + "document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h){if(!vis(h))return;var t=txtB(h,120);if(t){var lv=parseInt(h.tagName.charAt(1),10);var pf='';for(var k=0;k<lv;k++)pf+='#';out.push('');out.push(pf+' '+t)}});"
      + "var nL=0;"
      + "document.querySelectorAll('a').forEach(function(a){if(nL>=200)return;if(!vis(a))return;var t=txtB(a,80);if(!t)return;var href=a.getAttribute('href')||'';if(href&&href.indexOf('http')!==0){try{href=new URL(href,location.href).href}catch(e){}}nL++;out.push('- ['+t+']('+href+')')});"
      + "document.querySelectorAll('button,input[type=submit],input[type=button]').forEach(function(b){if(!vis(b))return;var t=txtB(b,60);if(t)out.push('[按钮 '+t+']')});"
      + "document.querySelectorAll('img').forEach(function(im){if(!vis(im))return;var alt=(im.getAttribute('alt')||'').trim();if(alt)out.push('[图: '+alt.substring(0,80)+']')});"
      + "document.querySelectorAll('table').forEach(function(tb){if(!vis(tb))return;tb.querySelectorAll('tr').forEach(function(tr){var cells=[];tr.querySelectorAll('th,td').forEach(function(c){cells.push(txtB(c,60))});if(cells.length)out.push('| '+cells.join(' | ')+' |')})});"
      + "var md=out.join(String.fromCharCode(10)).replace(/\\n{3,}/g,String.fromCharCode(10)+String.fromCharCode(10));"
      + "if(md.length>30000)md=md.substring(0,30000)+String.fromCharCode(10)+'...[截断]';"
      + "return JSON.stringify({href:location.href,ready:document.readyState,md:md})"
      + "}catch(e){return JSON.stringify({href:'',ready:'err',md:'',err:String(e)})}})()"
  }

  /** P12b: 紧凑 Markdown 快照（可见内容、剔除噪音、30000 字符上限）。
   * [P62-A] bridge-free：自包含表达式 + settle 重试 + payload 校验。表单提交导航后注入桥已死，
   * 旧探针会读到半提交文档的原始 HTML——现在对结果做三重校验：
   * ① 可解析为 {href,ready,md} ② md 非 raw-HTML 前缀且非过短 ③ readyState 已 settle。 */
  async snapshotMarkdown(): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_snapshot_md', 'BCP')
    if (!this.webviewController) {
      timer()
      return { success: false, data: null, error: 'WebView not bound' }
    }
    const expr = this.buildSnapshotMdExpr()
    let lastErr = ''
    for (let attempt = 0; attempt < 3; attempt++) {
      const r = await this.executeJS(expr, Constants.BCP_SCRIPT_INJECT_TIMEOUT_MS)
      if (!r.success) {
        lastErr = `${r.error}`
      } else {
        let text = `${r.data}`
        if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
          try { text = JSON.parse(text) as string } catch (e) { }
        }
        try {
          const parsed = JSON.parse(text) as Record<string, Object>
          const md: string = parsed['md'] === undefined || parsed['md'] === null ? '' : `${parsed['md']}`
          const ready: string = parsed['ready'] === undefined || parsed['ready'] === null ? '' : `${parsed['ready']}`
          const perr: string = parsed['err'] === undefined || parsed['err'] === null ? '' : `${parsed['err']}`
          const head = md.trim().substring(0, 40)
          const rawHtml = /^<(style|html|head|script|meta|link|!|body)/i.test(head)
          if (perr) {
            lastErr = perr
          } else if (md.trim().length >= 5 && !rawHtml && (ready === 'complete' || ready === 'interactive')) {
            timer()
            return { success: true, data: md, error: null }
          } else {
            lastErr = rawHtml ? 'stale raw-HTML snapshot payload (mid-navigation document)' : 'document not settled (ready=' + ready + ', len=' + md.length + ')'
          }
        } catch (e) {
          lastErr = 'unparseable snapshot payload head: ' + text.substring(0, 60)
        }
      }
      if (attempt < 2) {
        await new Promise<void>((res) => setTimeout(res, 700))
      }
    }
    timer()
    return { success: false, data: null, error: 'snapshot_md failed after retries: ' + lastErr }
  }

  /** P55: Stable SnapshotRef —— 页面注入 data-bcp-ref 并收集 refs JSON（bridge 不在则先注入一次） */
  async collectRefs(): Promise<BCPResult> {
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    let result = await this.executeJS(`window.__bcp_refs ? window.__bcp_refs() : 'undefined'`)
    let dataStr = `${result.data}`
    if (!result.success || !dataStr || dataStr === 'undefined' || dataStr.startsWith('"undefined"')) {
      return { success: false, data: null, error: 'refs collection returned empty' }
    }
    if (dataStr.startsWith('"') && dataStr.endsWith('"')) {
      try {
        dataStr = JSON.parse(dataStr) as string
      } catch (e) {
      }
    }
    return { success: true, data: dataStr, error: null }
  }

  async getText(): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_get_text', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    const js = `window.__bcp_get_text(0);`
    const result = await this.executeJS(js)
    timer()
    return result
  }

  /** P17c: 页内查找 —— window.find(前向/后向+大小写不敏感)，
   *  无匹配数 API（ArkWeb 无 findAllMatcher 之类的计数），
   *  返回 'found' | 'none' | 'unsupported' | runtime error */
  async findText(query: string, forward: boolean): Promise<string> {
    if (!query || query.length === 0) {
      return 'none'
    }
    if (!this.webviewController) {
      ErrorHandler.handle(new AppError(ErrorCodes.BCP_001, 'WebView not bound'))
      return 'unsupported'
    }
    const esc = query.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
    const js = `(function(){ try { if (typeof window.find !== 'function') { return 'unsupported' } return window.find('${esc}', false, !${forward}, true) ? 'found' : 'none' } catch (e) { return 'err:' + e } })()`
    try {
      const r = await this.webviewController.runJavaScript(js)
      let v = `${r}`
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
        try { v = JSON.parse(v) as string } catch (e) { }
      }
      console.info('BCPEngine findText: ' + query + ' -> ' + v)
      return v
    } catch (e) {
      console.error('BCPEngine findText error: ' + e)
      return 'unsupported'
    }
  }

  async wait(ms: number): Promise<BCPResult> {
    return new Promise(resolve => {
      setTimeout(() => {
        resolve({ success: true, data: null, error: null })
      }, ms)
    })
  }

  async waitForElement(selector: string, timeoutMs: number = 5000): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_wait_for', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    const js = `window.__bcp_wait_for(${JSON.stringify(selector)}, ${timeoutMs}, 0);`
    const result = await this.executeJS(js, timeoutMs + Constants.BCP_SCRIPT_INJECT_TIMEOUT_MS)
    timer()
    return result
  }

  async back(): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_back', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    try {
      this.webviewController!.backward()
      timer()
      return { success: true, data: null, error: null }
    } catch (e) {
      timer()
      return { success: false, data: null, error: `${e}` }
    }
  }

  async forward(): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_forward', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    try {
      this.webviewController!.forward()
      timer()
      return { success: true, data: null, error: null }
    } catch (e) {
      timer()
      return { success: false, data: null, error: `${e}` }
    }
  }

  isBridgeInjected(): boolean {
    return this.bridgeInjected
  }

  getWebviewId(): string {
    return this.webviewId
  }
  /** [P43] evaluate: 在当前页面求值任意 JS 表达式，结果 JSON 序列化返回（MCP evaluate/run 宏/act 扩展 kinds 复用） */
  async evaluate(expression: string): Promise<BCPResult> {
    await this.settleIfJustRebound()
    const timer = PerformanceMonitor.startTimer('bcp_evaluate', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    try {
      // IIFE 包裹：表达式求值；页面侧异常以 {ok:false,error} 带回而非 reject
      const wrapped = `(function(){try{const r=(${expression});return JSON.stringify({ok:true,result:(r===undefined?null:r)})}catch(e){return JSON.stringify({ok:false,error:String(e)})}})()`
      // [P62-A] same never-settling hazard as executeJS — race with the standard inject timeout
      const raw = await Promise.race([
        this.webviewController!.runJavaScript(wrapped),
        new Promise<string>((res) => {
          setTimeout(() => res('__BCP_TIMEOUT__'), Constants.BCP_SCRIPT_INJECT_TIMEOUT_MS)
        })
      ])
      if (raw === '__BCP_TIMEOUT__') {
        timer()
        return { success: false, data: null, error: 'evaluate timeout (page navigating?)' }
      }
      timer()
      return { success: true, data: this.parseEvalJson(`${raw}`), error: null }
    } catch (e) {
      timer()
      return { success: false, data: null, error: `${e}` }
    }
  }

  /** [P43] 解析 runJavaScript 回传：剥 JSON 字符串引号 → JSON.parse；非合法 JSON 原样包装 */
  /** [P43] 解析 runJavaScript 回传：剥 JSON 字符串引号 → 校验合法 JSON 后原样返回（string）；非法则包装为 {ok,result} JSON 串 */
  private parseEvalJson(raw: string): string {
    let text = raw
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        text = JSON.parse(text) as string
      } catch (e) {
        console.warn('[BCPEngine] parseEvalJson unquote failed: ' + raw)
      }
    }
    try {
      JSON.parse(text)
      return text
    } catch (e) {
      const wrapped: Record<string, Object> = { 'ok': true, 'result': text }
      return JSON.stringify(wrapped)
    }
  }
}

export const BCPEngine = new BCPEngineImpl()
