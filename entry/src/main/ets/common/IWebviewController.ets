export interface IWebviewController {
  runJavaScript(script: string): Promise<string>
  loadUrl(url: string): void
  backward(): void
  forward(): void
  refresh(): void
  stop(): void
  getTitle(): string
  accessBackward(): boolean
  accessForward(): boolean
}
