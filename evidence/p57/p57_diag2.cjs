// P57 diag2: replicate harness flow (new session + new tab each) x8, dump failing snapshot full body
const http = require('http');
const T = process.argv[2];
let id = 0;
function rpc(m, p) { id++; return JSON.stringify({ jsonrpc: '2.0', id, method: m, params: p }); }
function post(qs, body, headers) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port: 19222, path: qs, method: 'POST',
      headers: Object.assign({ 'Content-Type': 'application/json' }, headers || {}) },
      (res) => { let d = ''; res.on('data', c => d += c); res.on('end', () => resolve({ code: res.statusCode, hdrs: res.headers, body: d })); });
    req.on('error', reject); req.setTimeout(15000, () => req.destroy(new Error('timeout')));
    req.end(body);
  });
}
(async () => {
  const qs = '/mcp?token=' + T;
  let fails = 0;
  for (let i = 0; i < 8; i++) {
    let r = await post(qs, rpc('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'diag2-' + i, version: '1.0' } }));
    const sid = r.hdrs['mcp-session-id'] || '';
    const sh = { 'Mcp-Session-Id': sid };
    await post(qs, rpc('tools/call', { name: 'tabs', arguments: { action: 'new', url: 'about:blank' } }), sh);
    r = await post(qs, rpc('tools/call', { name: 'navigate', arguments: { url: 'https://example.com' } }), sh);
    await new Promise(res => setTimeout(res, 4000));
    r = await post(qs, rpc('tools/call', { name: 'snapshot', arguments: {} }), sh);
    const ok = r.code === 200 && r.body.includes('"isError":false') && r.body.length > 200;
    console.log('sess' + i + ' len=' + r.body.length + ' ok=' + ok);
    if (!ok) { fails++; console.log('  FULL: ' + r.body); }
  }
  console.log('fails=' + fails + '/8');
  process.exit(0);
})().catch(e => { console.error('ERR: ' + e.message); process.exit(1); });
