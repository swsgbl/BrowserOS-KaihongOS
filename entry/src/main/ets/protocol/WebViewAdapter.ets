import { webview } from '@kit.ArkWeb'
import { IWebviewController } from '../common/IWebviewController'

/**
 * 适配器：将 @ohos.web.webview 的原生 WebviewController 适配为工程内 IWebviewController 接口。
 * 所有透传方法均已核对 since 版本 ≤ API 14（loadUrl/backward/forward/refresh/getTitle: 9, runJavaScript: 12）。
 */
export class WebViewAdapter implements IWebviewController {
  private controller: webview.WebviewController

  constructor(controller: webview.WebviewController) {
    this.controller = controller
  }

  getRawController(): webview.WebviewController {
    return this.controller
  }

  runJavaScript(script: string): Promise<string> {
    return this.controller.runJavaScript(script)
  }

  loadUrl(url: string): void {
    this.controller.loadUrl(url)
  }

  backward(): void {
    this.controller.backward()
  }

  forward(): void {
    this.controller.forward()
  }

  refresh(): void {
    this.controller.refresh()
  }

  stop(): void {
    this.controller.stop()
  }

  getTitle(): string {
    return this.controller.getTitle()
  }

  accessBackward(): boolean {
    return this.controller.accessBackward()
  }

  accessForward(): boolean {
    return this.controller.accessForward()
  }
}
