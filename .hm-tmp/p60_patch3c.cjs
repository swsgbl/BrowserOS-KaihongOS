// P60 补丁3 (final): 用正则定位 headText..data 构造块替换
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/HttpMcpTransport.ets';
let s = fs.readFileSync(P, 'utf8');
if (s.includes('P60 netstack: sending a 0-length')) { console.error('already patched'); process.exit(0); }
const re = / {4}const headText = headers\.join\(.(?:\\r\\n|\\n|.)\) \+ .(?:\\r\\n|\\n|\\r|.){4}.\r?\n {4}const headBytes = new util\.TextEncoder\(\)\.encodeInto\(headText\)\r?\n {4}const out = new Uint8Array\(headBytes\.length \+ bodyBytes\.length\)\r?\n {4}out\.set\(headBytes, 0\)\r?\n {4}out\.set\(bodyBytes, headBytes\.length\)\r?\n {4}const data = out\.buffer\.slice\(out\.byteOffset, out\.byteOffset \+ out\.length\)/;
const m = s.match(re);
if (!m) { console.error('regex no match'); process.exit(1); }
const nl = m[0].includes('\r\n') ? '\r\n' : '\n';
const newStr = [
  m[0].split(nl)[0],
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
s = s.replace(m[0], newStr);
fs.writeFileSync(P, s, 'utf8');
console.log('patch3 applied (nl=' + JSON.stringify(nl) + ')');
