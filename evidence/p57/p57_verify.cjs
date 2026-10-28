// P57 device verification: tools/list name, evaluate_in_page call, evaluate alias, read no-JS
const http = require('http');
const T = process.argv[2];
const HOST = '127.0.0.1', PORT = 19222;
let id = 0;
function rpc(method, params) { id++; return JSON.stringify({ jsonrpc: '2.0', id, method, params }); }
function post(qs, body, headers) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: HOST, port: PORT, path: qs, method: 'POST',
      headers: Object.assign({ 'Content-Type': 'application/json' }, headers || {}) },
      (res) => { let d = ''; res.on('data', c => d += c); res.on('end', () => resolve({ code: res.statusCode, hdrs: res.headers, body: d })); });
    req.on('error', reject); req.setTimeout(15000, () => { req.destroy(new Error('timeout')); });
    req.end(body);
  });
}
(async () => {
  const qs = '/mcp?token=' + T;
  const out = [];
  // 1. initialize
  let r = await post(qs, rpc('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'p57-verify', version: '1.0' } }));
  const sid = (r.hdrs['mcp-session-id'] || '');
  out.push('[1] initialize code=' + r.code + ' sid=' + sid.substring(0, 8) + '...');
  const sh = { 'Mcp-Session-Id': sid };
  // 2. tools/list
  r = await post(qs, rpc('tools/list', {}), sh);
  const names = (JSON.parse(r.body).result.tools || []).map(t => t.name);
  out.push('[2] tools/list count=' + names.length);
  out.push('    has evaluate_in_page=' + names.includes('evaluate_in_page') + ' has evaluate(old)=' + names.includes('evaluate'));
  const evTool = (JSON.parse(r.body).result.tools || []).find(t => t.name === 'evaluate_in_page');
  out.push('    evaluate_in_page aliases=' + JSON.stringify(evTool && evTool.aliases));
  // 3. session tab
  r = await post(qs, rpc('tools/call', { name: 'tabs', arguments: { action: 'new', url: 'about:blank' } }), sh);
  out.push('[3] tabs new code=' + r.code);
  // 4. navigate example.com
  r = await post(qs, rpc('tools/call', { name: 'navigate', arguments: { url: 'https://example.com' } }), sh);
  out.push('[4] navigate code=' + r.code);
  await new Promise(res => setTimeout(res, 5000));
  // 5. evaluate_in_page
  r = await post(qs, rpc('tools/call', { name: 'evaluate_in_page', arguments: { expression: '1+2*3' } }), sh);
  out.push('[5] evaluate_in_page 1+2*3 -> ' + r.body.substring(0, 160));
  // 6. evaluate alias
  r = await post(qs, rpc('tools/call', { name: 'evaluate', arguments: { expression: 'document.title' } }), sh);
  out.push('[6] evaluate(alias) document.title -> ' + r.body.substring(0, 160));
  // 7. read (snapshot pipeline, no per-call JS)
  r = await post(qs, rpc('tools/call', { name: 'read', arguments: {} }), sh);
  const rb = JSON.stringify(r.body);
  out.push('[7] read code=' + r.code + ' source=snapshot=' + (rb.includes('snapshot') || r.body.includes('snapshot')) + ' len=' + r.body.length);
  out.push('    read sample: ' + r.body.substring(0, 200));
  console.log(out.join('\n'));
  process.exit(0);
})().catch(e => { console.error('ERR: ' + e.message); process.exit(1); });
