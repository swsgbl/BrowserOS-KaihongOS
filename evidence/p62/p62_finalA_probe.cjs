// Final A verdict with sensitiveConfirm=true: agent-style flow (#kw/#su, non-sensitive selectors)
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
  await rpc('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'final-a', version: '1' } });
  await rpc('notifications/initialized', undefined, false);
  const t = await call('tabs', { action: 'new', url: 'https://www.baidu.com' });
  await sleep(3500);
  const before = await call('snapshot', {});
  console.log('BEFORE len=' + before.t.length);

  await call('act', { kind: 'type_at', ref: '#kw', text: '上海天气', clear: true });
  const ck = await call('act', { kind: 'click', ref: '#su' }, 40000);
  console.log('click #su:', ck.err ? 'ERR ' + ck.t.slice(0, 120) : ck.t.slice(0, 150));
  await sleep(3000);

  const after = await call('read', {});
  const hasWeather = /(天气|°C|℃)/.test(after.t);
  const cssPollution = after.t.includes('<style');
  const g = await call('grep', { pattern: '天气|°C' });
  let hits = 0;
  try { hits = JSON.parse(g.t).count; } catch (e) { hits = (g.t.match(/天气/g) || []).length; }
  console.log('AFTER read len=' + after.t.length + ' weather=' + hasWeather + ' cssPollution=' + cssPollution + ' grepHits=' + hits);
  const href = await call('evaluate_in_page', { expression: 'location.href' });
  console.log('href:', href.t.slice(0, 130));
  const verdict = hasWeather && !cssPollution && after.t.length > 5000 && before.t.length !== after.t.length;
  console.log(verdict ? '*** FINAL A VERDICT: PASS (fresh, clean, weather readable) ***' : '*** FINAL A VERDICT: FAIL ***');
  try { const tabId = JSON.parse(t.t).tabId; await call('tabs', { action: 'close', tabId }); } catch (e) {}
  process.exit(verdict ? 0 : 1);
})().catch((e) => { console.log('FATAL', e.message); process.exit(1); });
