// P53: handleUpload 语义修正（UI 闭环已通，MCP 面如实标注）
const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/MCPServer.ets'
let t = fs.readFileSync(P, 'utf8')
const crlf = t.includes('\r\n')
function norm(s) { return crlf ? s.replace(/\n/g, '\r\n') : s }

const old = norm("  private handleUpload: ToolHandler = async (params, agentId) => {\n" +
  "    const rec23: Record<string, Object> = { 'error': 'unsupported on ArkWeb', 'supported': false, 'detail': 'requires onFileSelectorShow wiring (deferred)' }\n" +
  "    return this.okResponse(rec23)\n" +
  "  }")
const nw = norm("  private handleUpload: ToolHandler = async (params, agentId) => {\n" +
  "    // P53: onShowFileSelector 已接线 —— 页面 <input type=file> 的 click 会拉起系统文件选择器，\n" +
  "    // 用户完成选择后文件直接注入页面（UI 闭环）。MCP 程序化指定 filePath 的注入仍受沙盒限制（同上游）。\n" +
  "    const rec23: Record<string, Object> = {\n" +
  "      'supported': true,\n" +
  "      'mode': 'interactive',\n" +
  "      'detail': 'click a file input on the page to trigger the system picker (onShowFileSelector); programmatic filePath injection is sandbox-restricted'\n" +
  "    }\n" +
  "    return this.okResponse(rec23)\n" +
  "  }")
if (!t.includes(old)) { console.error('MISS handleUpload'); process.exit(1) }
t = t.replace(old, nw)
fs.writeFileSync(P, t, 'utf8')
console.log('OK: handleUpload semantic updated')
