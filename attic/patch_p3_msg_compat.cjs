// P3 fix2 v2: surgical — replace only the onBytes call line with compat shim + evidence log
const fs = require('fs');
const p = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/HttpMcpTransport.ets';
let s = fs.readFileSync(p, 'utf8');

const old = '        this.onBytes(conn, new Uint8Array(info.message))';
const now = [
  '        // KaihongOS netstack compat: new signature passes SocketMessageInfo{message}, legacy passes ArrayBuffer directly',
  '        const raw: Object = info as Object',
  '        const ab: ArrayBuffer = (raw !== undefined && raw !== null &&',
  '          (raw as socket.SocketMessageInfo).message !== undefined)',
  '          ? (raw as socket.SocketMessageInfo).message : raw as ArrayBuffer',
  `        console.info(\`[\${TAG}] onMessage id=\${client.clientId} bytes=\${ab.byteLength}\`)`,
  '        this.onBytes(conn, new Uint8Array(ab))'
].join('\r\n');

if (!s.includes(old)) { console.error('ANCHOR LINE NOT FOUND'); process.exit(1); }
if (s.includes('netstack compat')) { console.log('already patched'); process.exit(0); }
s = s.replace(old, now);
fs.writeFileSync(p, s);
console.log('MSG COMPAT PATCH v2 OK');
