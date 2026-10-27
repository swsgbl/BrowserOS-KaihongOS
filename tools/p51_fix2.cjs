const fs = require('fs')
const f = 'entry/src/main/ets/service/MCPServer.ets'
let s = fs.readFileSync(f, 'utf8')
const D = '\r\n'
const start = s.indexOf('/** P51: tools that require')
const endMarker = "'download', 'upload']"
const end = s.indexOf(endMarker, start)
if (start < 0 || end < 0) { console.error('block not found'); process.exit(1) }
const block = s.substring(start, end + endMarker.length)
// remove block (plus one trailing blank line if present)
let after = s.substring(0, start) + s.substring(end + endMarker.length)
if (after.includes(D + D + D)) { /* leave as-is */ }
const anchor = "import { util } from '@kit.ArkTS'"
const ai = after.indexOf(anchor)
if (ai < 0) { console.error('anchor not found'); process.exit(1) }
const insertAt = ai + anchor.length
s = after.substring(0, insertAt) + D + D + block + D + after.substring(insertAt)
fs.writeFileSync(f, s, 'utf8')
console.log('relocated, block len=' + block.length)
