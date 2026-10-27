// fix: move PAGE_TOOLS below all imports in MCPServer.ets
const fs = require('fs')
const FILE = 'entry/src/main/ets/service/MCPServer.ets'
let s = fs.readFileSync(FILE, 'utf8')
const D = s.includes('\r\n') ? '\r\n' : '\n'
const block =
  '/** P51: tools that require a routed page (session must own a tab) */' + D +
  "const PAGE_TOOLS: string[] = ['navigate', 'snapshot', 'diff', 'act', 'click', 'type', 'scroll', 'read', 'getText'," + D +
  "  'grep', 'screenshot', 'pdf', 'wait', 'evaluate', 'run', 'download', 'upload']" + D + D
if (!s.includes(block)) { console.error('MISS block'); process.exit(1) }
s = s.replace(block, '')
// insert after the LAST import line (anchor: cryptoFramework/util imports then blank)
const anchor = "import { util } from '@kit.ArkTS'"
if (!s.includes(anchor)) { console.error('MISS anchor'); process.exit(1) }
s = s.replace(anchor, anchor + D + D + block.replace(D + D + '$', D + D), )
// The block already ends with D; ensure exactly one blank line then type ToolHandler
fs.writeFileSync(FILE, s, 'utf8')
console.log('PAGE_TOOLS relocated')
