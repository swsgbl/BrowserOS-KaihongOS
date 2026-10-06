// P3 diag v10: dump first-frame bytes at onBytes entry
const fs = require('fs');
const p = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/HttpMcpTransport.ets';
let s = fs.readFileSync(p, 'utf8');
const anchor = '  private onBytes(conn: ConnectionState, chunk: Uint8Array): void {\r\n    let buf = this.concatBytes(conn.buffer, chunk)';
const inject = `  private onBytes(conn: ConnectionState, chunk: Uint8Array): void {\r\n    let buf = this.concatBytes(conn.buffer, chunk)\r\n    let hex0 = ''\r\n    for (let k = 0; k < Math.min(buf.length, 24); k++) {\r\n      hex0 += buf[k].toString(16).padStart(2, '0') + ' '\r\n    }\r\n    console.info(\`[\${TAG}] onBytes id=\${conn.client.clientId} len=\${buf.length} head=\${hex0}\`)`;
if (!s.includes(anchor)) { console.error('ANCHOR NOT FOUND'); process.exit(1); }
if (s.includes('onBytes id=')) { console.log('already'); process.exit(0); }
s = s.replace(anchor, inject);
fs.writeFileSync(p, s);
console.log('DIAG v10 OK');
