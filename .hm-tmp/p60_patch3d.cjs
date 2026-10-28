// P60 补丁3 (final2): 精确字符串替换
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/HttpMcpTransport.ets';
let s = fs.readFileSync(P, 'utf8');
if (s.includes('P60 netstack: sending a 0-length')) { console.error('already patched'); process.exit(0); }

// 源码里 join('\r\n') 的 \r\n 是字面 4 字符转义序列 (backslash r backslash n)
const BS = String.fromCharCode(92); // backslash
const escRN = BS + 'r' + BS + 'n';  // 源码中的 \r\n 字面量 (4 chars)
const L1 = "    const headText = headers.join('" + escRN + "') + '" + escRN + escRN + "'";
const L2 = "    const headBytes = new util.TextEncoder().encodeInto(headText)";
const L3 = "    const out = new Uint8Array(headBytes.length + bodyBytes.length)";
const L4 = "    out.set(headBytes, 0)";
const L5 = "    out.set(bodyBytes, headBytes.length)";
const L6 = "    const data = out.buffer.slice(out.byteOffset, out.byteOffset + out.length)";
const oldBlock = [L1, L2, L3, L4, L5, L6].join('\n');

if (!s.includes(oldBlock)) {
  console.error('block not found; trying CR check...');
  console.error('has L1 alone:', s.includes(L1));
  process.exit(1);
}
const newBlock = [
  L1,
  L2,
  '    // P60 netstack: sending a 0-length ArrayBuffer throws — for empty bodies (202 notifications)',
  '    // send the header bytes alone instead of concatenating an empty tail.',
  '    let data: ArrayBuffer',
  '    if (bodyBytes.length === 0) {',
  '      data = headBytes.buffer.slice(headBytes.byteOffset, headBytes.byteOffset + headBytes.length)',
  '    } else {',
  '      const out = new Uint8Array(headBytes.length + bodyBytes.length)',
  '      out.set(headBytes, 0)',
  '      out.set(bodyBytes, headBytes.length)',
  '      data = out.buffer.slice(out.byteOffset, out.byteOffset + out.length)',
  '    }',
].join('\n');
s = s.replace(oldBlock, newBlock);
fs.writeFileSync(P, s, 'utf8');
console.log('patch3 applied OK');
