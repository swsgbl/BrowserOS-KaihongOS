// P60 补丁2: sendSimple 空 body 守卫
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/HttpMcpTransport.ets';
let s = fs.readFileSync(P, 'utf8');
const oldStr = '    const bodyBytes = new util.TextEncoder().encodeInto(bodyText)';
if (!s.includes(oldStr)) { console.error('anchor missing'); process.exit(1); }
if (s.includes('P60: encodeInto')) { console.error('already patched'); process.exit(0); }
const newStr = [
  '    // P60: encodeInto(\'\') returns undefined on this netstack (same family as P4 decodeWithStream)',
  '    // — notification responses carry an EMPTY body, so guard the empty case explicitly.',
  '    const bodyBytes = bodyText.length === 0 ? new Uint8Array(0) : new util.TextEncoder().encodeInto(bodyText)',
].join('\r\n');
s = s.replace(oldStr, newStr);
fs.writeFileSync(P, s, 'utf8');
console.log('sendSimple empty-body guard patched');
