
import { BCPResult } from '../common/Types'
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

  bindWebView(webviewController: IWebviewController, webviewId: string): void {
    this.webviewController = webviewController
    this.webviewId = webviewId
    this.bridgeInjected = false
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
      const result = await this.webviewController.runJavaScript(jsCode)
      timer()
      return { success: true, data: result, error: null }
    } catch (e) {
      timer()
      return { success: false, data: null, error: `${e}` }
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

  async click(selector: string): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_click', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    const js = `window.__bcp_click(${JSON.stringify(selector)}, 0);`
    const result = await this.executeJS(js)
    timer()
    return result
  }

  async type(selector: string, text: string): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_type', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    const js = `window.__bcp_type(${JSON.stringify(selector)}, ${JSON.stringify(text)}, 0);`
    const result = await this.executeJS(js)
    timer()
    return result
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

  /** P12b: 紧凑 Markdown 快照（可见内容、剔除噪音、30000 字符上限；同步表达式求值，不依赖回调 proxy） */
  async snapshotMarkdown(): Promise<BCPResult> {
    const timer = PerformanceMonitor.startTimer('bcp_snapshot_md', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    // 先尝试直接执行（bridge 若在当前文档存活）；undefined 则重注入一次再执行（换页后 window 函数会丢）
    let result = await this.executeJS(`window.__bcp_snapshot_md ? window.__bcp_snapshot_md() : 'undefined'`)
    if (!result.data || `${result.data}` === 'undefined' || `${result.data}`.startsWith('"undefined"')) {
      try {
        this.webviewController!.runJavaScript(JSBridgeInjector.getBridgeScript())
        result = await this.executeJS(`window.__bcp_snapshot_md ? window.__bcp_snapshot_md() : 'undefined'`)
      } catch (e) {
        timer()
        return { success: false, data: null, error: `re-inject failed: ${e}` }
      }
    }
    timer()
    let dataStr = `${result.data}`
    // runJavaScript 对字符串结果会再包一层 JSON 引号，解包
    if (dataStr.length >= 2 && dataStr.startsWith('"') && dataStr.endsWith('"')) {
      try {
        dataStr = JSON.parse(dataStr) as string
      } catch (e) {
        // 保持原样
      }
    }
    if (dataStr.startsWith('__SNAP_ERR__')) {
      return { success: false, data: null, error: dataStr.substring('__SNAP_ERR__'.length) }
    }
    if (!dataStr || dataStr === 'undefined') {
      return { success: false, data: null, error: 'snapshot_md returned empty' }
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
    const timer = PerformanceMonitor.startTimer('bcp_evaluate', 'BCP')
    const bridgeReady = await this.ensureBridge()
    if (!bridgeReady) {
      timer()
      return { success: false, data: null, error: ErrorCodes.getMessage(ErrorCodes.BCP_001) }
    }
    try {
      // IIFE 包裹：表达式求值；页面侧异常以 {ok:false,error} 带回而非 reject
      const wrapped = `(function(){try{const r=(${expression});return JSON.stringify({ok:true,result:(r===undefined?null:r)})}catch(e){return JSON.stringify({ok:false,error:String(e)})}})()`
      const raw = await this.webviewController!.runJavaScript(wrapped)
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