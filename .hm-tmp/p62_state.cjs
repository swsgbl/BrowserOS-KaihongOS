// quick state check: what tabs/urls exist now
const http = require('http');
const { URL } = require('url');
const MCP_URL = process.argv[2];
let SESSION = null;
let id = 1;
function post(bodyObj, timeoutMs) {
  return new Promise((resolve, reject) => {
    const u = new URL(MCP_URL);
    const body = JSON.stringify(bodyObj);
    const headers = { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) };
    if (SESSION) headers['Mcp-Session-Id'] = SESSION;
    const req = http.request({ hostname: u.hostname, port: u.port, path: u.pathname + u.search, method: 'POST', headers, timeout: timeoutMs }, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => {
        const sid = res.headers['mcp-session-id'];
        if (sid) SESSION = sid;
        let j = null; try { j = JSON.parse(d); } catch (e) { /* */ }
        resolve({ status: res.statusCode, json: j, text: d });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.write(body); req.end();
  });
}
(async () => {
  await post({ jsonrpc: '2.0', id: id++, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'state', version: '0' } } }, 15000);
  await post({ jsonrpc: '2.0', method: 'notifications/initialized' }, 15000);
  const r = await post({ jsonrpc: '2.0', id: id++, method: 'tools/call', params: { name: 'tabs', arguments: { action: 'list' } } }, 30000);
  const res = r.json && r.json.result;
  const text = Array.isArray(res && res.content) ? res.content.map((c) => c.text || '').join('\n') : r.text;
  console.log('TABS:', text.slice(0, 800));
  const w = await post({ jsonrpc: '2.0', id: id++, method: 'tools/call', params: { name: 'evaluate_in_page', arguments: { expression: 'location.href' } } }, 30000);
  const wres = w.json && w.json.result;
  console.log('EVAL href:', (wres && wres.content ? wres.content.map((c) => c.text).join('') : w.text).slice(0, 300));
})().catch((e) => console.log('ERR', e.message));
