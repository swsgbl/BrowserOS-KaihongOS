// P3 fix: token persist block was inserted AFTER `return true` (dead code).
// Move it BEFORE return: remove the first `return true` so block becomes reachable.
const fs = require('fs');
const p = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/MCPServer.ets';
let s = fs.readFileSync(p, 'utf8');
const dead = "console.info('[MCPServer] started, HTTP transport listening on 0.0.0.0:' + this.port)\r\n    return true\r\n";
if (!s.includes(dead)) { console.error('DEAD PATTERN NOT FOUND'); process.exit(1); }
const live = "console.info('[MCPServer] started, HTTP transport listening on 0.0.0.0:' + this.port)\r\n";
s = s.replace(dead, live);
fs.writeFileSync(p, s);
// verify: exactly one `return true` remains in start() and it is after the persist block
const seg = s.slice(s.indexOf('async start(port'), s.indexOf('async stop()'));
const returns = (seg.match(/return true/g) || []).length;
const order = seg.indexOf('authToken persisted') < seg.indexOf('return true');
console.log('return-true count in start():', returns, '| persist-before-return:', order);
if (returns !== 1 || !order) { console.error('FIX VERIFY FAILED'); process.exit(1); }
console.log('FIX OK');
