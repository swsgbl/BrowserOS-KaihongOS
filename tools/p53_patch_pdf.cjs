// P53: PDF 闭环 —— IWebviewController + WebViewAdapter 加 createPdf；BCPEngine 暴露 pdf 导出；MCPServer handlePdf 真实现
const fs = require('fs')

function rep(file, oldStr, newStr, label) {
  let t = fs.readFileSync(file, 'utf8')
  const crlf = t.includes('\r\n')
  const o = crlf ? oldStr.replace(/\n/g, '\r\n') : oldStr
  const nw = crlf ? newStr.replace(/\n/g, '\r\n') : newStr
  if (!t.includes(o)) { console.error('MISS [' + file.split('/').pop() + ']: ' + label); process.exit(1) }
  t = t.split(o).join(nw)
  fs.writeFileSync(file, t, 'utf8')
  console.log('OK', file.split('/').pop(), '-', label)
}

const ROOT = 'D:/BrowserOS - KaihongOS/entry/src/main/ets'

// 1. IWebviewController 接口加 createPdf
rep(ROOT + '/common/IWebviewController.ets',
  '  accessForward(): boolean\n}',
  '  accessForward(): boolean\n  createPdf(widthIn: number, heightIn: number, margins: number, printBackground: boolean): Promise<Uint8Array>\n}',
  'iface createPdf')

// 2. WebViewAdapter 实现（createPdf since 14, PDF 配置单位英寸）
rep(ROOT + '/protocol/WebViewAdapter.ets',
  '  accessForward(): boolean {\n    return this.controller.accessForward()\n  }\n}',
  '  accessForward(): boolean {\n    return this.controller.accessForward()\n  }\n\n  createPdf(widthIn: number, heightIn: number, margins: number, printBackground: boolean): Promise<Uint8Array> {\n    const cfg: webview.PdfConfiguration = {\n      width: widthIn,\n      height: heightIn,\n      marginTop: margins,\n      marginBottom: margins,\n      marginRight: margins,\n      marginLeft: margins,\n      scale: 1.0,\n      shouldPrintBackground: printBackground\n    }\n    return this.controller.createPdf(cfg).then((data: webview.PdfData): Uint8Array => data.pdfArrayBuffer())\n  }\n}',
  'adapter createPdf')

// 3. BCPEngine 加 createPdf 方法（绑定校验同 navigate）
rep(ROOT + '/protocol/BCPEngine.ets',
  '  async click(selector: string): Promise<BCPResult> {',
  '  /** P53: 当前页导出 PDF（WebviewController.createPdf, since 14）。返回 base64（大负载截断策略同 screenshot） */\n  async createPdf(): Promise<BCPResult> {\n    if (!this.webviewController) {\n      return { success: false, data: null, error: \'WebView not bound\' }\n    }\n    try {\n      const buf = await this.webviewController.createPdf(8.27, 11.69, 0.4, true)\n      const b64 = util.Base64Helper.encodeToStringSync(buf)\n      // 上限 12MB base64 —— 超限截断报错（HTTP 层另有整体限制）\n      if (b64.length > 12 * 1024 * 1024) {\n        return { success: false, data: null, error: \'pdf too large (>12MB base64)\' }\n      }\n      return { success: true, data: b64, error: null }\n    } catch (e) {\n      return { success: false, data: null, error: `${e}` }\n    }\n  }\n\n  async click(selector: string): Promise<BCPResult> {',
  'engine createPdf')

// 4. BCPEngine import util 检查
{
  const t = fs.readFileSync(ROOT + '/protocol/BCPEngine.ets', 'utf8')
  if (!/import \{ util \} from '@kit.ArkTS'/.test(t)) {
    const ia = t.indexOf("import { BCPResult }")
    const lineEnd = t.indexOf('\n', ia)
    let tt = t.slice(0, lineEnd + 1) + "import { util } from '@kit.ArkTS'\r\n" + t.slice(lineEnd + 1)
    fs.writeFileSync(ROOT + '/protocol/BCPEngine.ets', tt, 'utf8')
    console.log('OK BCPEngine - util import added')
  }
}

// 5. MCPServer handlePdf 真实现
rep(ROOT + '/service/MCPServer.ets',
  "  private handlePdf: ToolHandler = async (params, agentId) => {\n    const rec25: Record<string, Object> = { 'error': 'unsupported on ArkWeb', 'supported': false }\n    return this.okResponse(rec25)\n  }",
  "  private handlePdf: ToolHandler = async (params, agentId) => {\n    // P53: 真实现 —— WebviewController.createPdf (since 14)，A4 纵向 + 打印背景\n    const result = await BCPEngine.createPdf()\n    if (!result.success) {\n      const recFail: Record<string, Object> = { 'supported': true, 'error': result.error || 'createPdf failed' }\n      return this.okResponse(recFail)\n    }\n    const data: MCPResponseData = { result: result.data === null ? null : `${result.data}` }\n    return this.bcpToMcpResponse(result, data)\n  }",
  'mcp handlePdf')

// 6. McpJsonRpcCore 工具描述符更新（upload + pdf）
rep(ROOT + '/service/McpJsonRpcCore.ets',
  "    tools.push(this.toolDef('upload', 'File upload — unsupported on ArkWeb in this build (onFileSelectorShow wiring deferred)',",
  "    tools.push(this.toolDef('upload', 'File upload — page <input type=file> triggers system file picker (onShowFileSelector wired P53)',",
  'descriptor upload')

rep(ROOT + '/service/McpJsonRpcCore.ets',
  "    tools.push(this.toolDef('pdf', 'Print page to PDF — unsupported on ArkWeb in this build', this.propMap([]), [], []))",
  "    tools.push(this.toolDef('pdf', 'Print page to PDF (A4 portrait, background on) — returns base64 PDF; implemented via WebviewController.createPdf since API 14', this.propMap([]), [], []))",
  'descriptor pdf')

console.log('ALL DONE')
