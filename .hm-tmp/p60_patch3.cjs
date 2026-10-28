// P60 补丁3: 空 body 时直接发 headBytes, 不拼 0 长度 ArrayBuffer (netstack send 对空 data 抛异常)
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/HttpMcpTransport.ets';
let s = fs.readFileSync(P, 'utf8');
const oldStr = [
  '    const headText = headers.join(\'\\r\\n\') + \'\\r\\n\\r\\n\'',
  '    const headBytes = new util.TextEncoder().encodeInto(headText)',
  '    const out = new Uint8Array(headBytes.length + bodyBytes.length)',
  '    out.set(headBytes, 0)',
  '    out.set(bodyBytes, headBytes.length)',
  '    const data = out.buffer.slice(out.byteOffset, out.byteOffset + out.length)',
].join('\r\n');
if (!s.includes(oldStr)) { console.error('anchor missing'); process.exit(1); }
if (s.includes('P60 netstack: sending a 0-length')) { console.error('already patched'); process.exit(0); }
const newStr = [
  '    const headText = headers.join(\'\\r\\n\') + \'\\r\\n\\r\\n\'',
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
].join('\r\n');
s = s.replace(oldStr, newStr);
fs.writeFileSync(P, s, 'utf8');
console.log('patch3: empty-body head-only send patched');
