// P60 补丁3 (LF 版本): 空 body 时直接发 headBytes
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/HttpMcpTransport.ets';
let s = fs.readFileSync(P, 'utf8');
const nl = s.includes("join('\r\n') + '\r\n\r\n'") ? '\r\n' : '\n';
const oldStr = [
  "    const headText = headers.join('" + nl + nl + "') + '" + nl + nl + nl + nl + "'",
  '    const headBytes = new util.TextEncoder().encodeInto(headText)',
  '    const out = new Uint8Array(headBytes.length + bodyBytes.length)',
  '    out.set(headBytes, 0)',
  '    out.set(bodyBytes, headBytes.length)',
  '    const data = out.buffer.slice(out.byteOffset, out.byteOffset + out.length)',
].join(nl);
if (!s.includes(oldStr)) { console.error('anchor missing, nl=' + JSON.stringify(nl)); process.exit(1); }
if (s.includes('P60 netstack: sending a 0-length')) { console.error('already patched'); process.exit(0); }
const newStr = [
  "    const headText = headers.join('" + nl + nl + "') + '" + nl + nl + nl + nl + "'",
  '    const headBytes = new util.TextEncoder().encodeInto(headText)',
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
].join(nl);
s = s.replace(oldStr, newStr);
fs.writeFileSync(P, s, 'utf8');
console.log('patch3 (nl=' + JSON.stringify(nl) + ') applied');
