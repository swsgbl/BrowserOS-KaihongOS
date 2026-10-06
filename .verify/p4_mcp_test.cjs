const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe" -t 127.0.0.1:15566 shell ';
function sh(cmd) { return execSync(HDC + '"' + cmd + '"', { encoding: 'utf8', timeout: 20000 }).trim(); }

const token = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt');
console.log('token=' + token);
if (!token || token.length < 8) { console.log('BAD TOKEN'); process.exit(1); }

async function main() {
  // tools/list: verify getText (not get_text)
  let r = await fetch('http://127.0.0.1:9222/mcp?token=' + token, {
    method: 'POST', signal: AbortSignal.timeout(8000),
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' })
  });
  let j = await r.json();
  const names = (j.result && j.result.tools) ? j.result.tools.map(t => t.name) : [];
  console.log('tools/list -> ' + r.status);
  console.log('  getText present: ' + names.includes('getText'));
  console.log('  get_text absent: ' + !names.includes('get_text'));
  console.log('  all: ' + names.join(','));

  // tools/call getText
  r = await fetch('http://127.0.0.1:9222/mcp?token=' + token, {
    method: 'POST', signal: AbortSignal.timeout(8000),
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'getText', arguments: {} } })
  });
  j = await r.json();
  console.log('tools/call getText -> ' + r.status + ' ' + JSON.stringify(j).slice(0, 200));

  // initialize (session header)
  r = await fetch('http://127.0.0.1:9222/mcp?token=' + token, {
    method: 'POST', signal: AbortSignal.timeout(8000),
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'p4test', version: '1' } } })
  });
  j = await r.json();
  console.log('initialize -> ' + r.status + ' session=' + (r.headers.get('mcp-session-id') || 'none') + ' server=' + (j.result && j.result.serverInfo ? j.result.serverInfo.name : JSON.stringify(j).slice(0, 120)));
}
main().catch(e => { console.log('FATAL ' + e.message); process.exit(1); });
