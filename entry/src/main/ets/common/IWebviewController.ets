export interface IWebviewController {
  runJavaScript(script: string): Promise<string>
  loadUrl(url: string): void
  backward(): void
  forward(): void
  refresh(): void
  getTitle(): string
  accessBackward(): boolean
  accessForward(): boolean
}
