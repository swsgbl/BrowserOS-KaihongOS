
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
}

export const BCPEngine = new BCPEngineImpl()