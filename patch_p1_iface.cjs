const fs = require('fs');

// 1. IWebviewController: add accessBackward/accessForward (both <= API14: 9/11)
const ip = 'D:\\BrowserOS - KaihongOS\\entry\\src\\main\\ets\\common\\IWebviewController.ets';
fs.writeFileSync(ip,
`export interface IWebviewController {
  runJavaScript(script: string): Promise<string>
  loadUrl(url: string): void
  backward(): void
  forward(): void
  refresh(): void
  getTitle(): string
  accessBackward(): boolean
  accessForward(): boolean
}
`);
console.log('OK: IWebviewController');

// 2. WebViewAdapter: implement them (pass-through) - file uses LF
const ap = 'D:\\BrowserOS - KaihongOS\\entry\\src\\main\\ets\\protocol\\WebViewAdapter.ets';
let a = fs.readFileSync(ap, 'utf8');
a = a.replace("  getTitle(): string {\n    return this.controller.getTitle()\n  }\n}",
"  getTitle(): string {\n    return this.controller.getTitle()\n  }\n\n  accessBackward(): boolean {\n    return this.controller.accessBackward()\n  }\n\n  accessForward(): boolean {\n    return this.controller.accessForward()\n  }\n}");
fs.writeFileSync(ap, a);
console.log('OK: WebViewAdapter ->', a.includes('accessBackward(): boolean') ? 'patched' : 'FAIL');
