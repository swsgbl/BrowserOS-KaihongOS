// A-root-cause: does type_at actually set the input value? does click navigate?
const http = require('http');
const { URL } = require('url');
const MCP = process.argv[2];
let S = null, id = 1;
function post(body, tmo) {
  return new Promise((res, rej) => {
    const u = new URL(MCP);
    const data = JSON.stringify(body);
    const h = { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) };
    if (S) h['Mcp-Session-Id'] = S;
    const req = http.request({ hostname: u.hostname, port: u.port, path: u.pathname + u.search, method: 'POST', headers: h, timeout: tmo }, (r) => {
      let d = '';
      r.on('data', (c) => (d += c));
      r.on('end', () => { const sid = r.headers['mcp-session-id']; if (sid) S = sid; let j = null; try { j = JSON.parse(d); } catch (e) {} res({ j, t: d }); });
    });
    req.on('error', rej);
    req.on('timeout', () => { req.destroy(); rej(new Error('timeout')); });
    req.write(data); req.end();
  });
}
async function rpc(m, p, withId = true, tmo = 45000) {
  const b = { jsonrpc: '2.0', method: m };
  if (withId) b.id = id++;
  if (p !== undefined) b.params = p;
  return post(b, tmo);
}
async function call(n, a, tmo = 45000) {
  const r = await rpc('tools/call', { name: n, arguments: a }, true, tmo);
  if (r.j && r.j.error) return { err: true, t: JSON.stringify(r.j.error) };
  const res = r.j && r.j.result;
  return { err: !!(res && res.isError), t: Array.isArray(res && res.content) ? res.content.map((c) => c.text || '').join('\n') : JSON.stringify(res) };
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
(async () => {
  await rpc('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'a-diag', version: '1' } });
  await rpc('notifications/initialized', undefined, false);
  const t = await call('tabs', { action: 'new', url: 'https://www.baidu.com' });
  console.log('tabs.new:', t.t.slice(0, 90));
  await sleep(3500);

  const ty = await call('act', { kind: 'type_at', ref: "input[name='wd']", text: 'harmonyos', clear: true });
  console.log('type_at:', ty.t.slice(0, 90));

  const v = await call('evaluate_in_page', { expression: "document.querySelector(\"input[name='wd']\")?.value ?? 'NO-INPUT'" });
  console.log('input value after type_at:', v.t.slice(0, 120));

  const ck = await call('act', { kind: 'click', ref: "input[type='submit']" }, 40000);
  console.log('click:', ck.t.slice(0, 120));
  await sleep(2500);

  const h = await call('evaluate_in_page', { expression: 'location.href' });
  console.log('href after click:', h.t.slice(0, 160));

  // cleanup
  try { const tabId = JSON.parse(t.t).tabId; await call('tabs', { action: 'close', tabId }); } catch (e) {}
})().catch((e) => console.log('FATAL', e.message));
