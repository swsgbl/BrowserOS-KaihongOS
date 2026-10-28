// A-fix verification via NON-sensitive click: iana.org root -> click "Domains" nav link -> snapshot must show new page
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
  await rpc('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'a-fix', version: '1' } });
  await rpc('notifications/initialized', undefined, false);
  const t = await call('tabs', { action: 'new', url: 'https://www.iana.org' });
  console.log('tabs.new:', t.t.slice(0, 80));
  await sleep(3500);
  const before = await call('snapshot', {});
  console.log('snapshot BEFORE len=' + before.t.length + ' head: ' + before.t.replace(/\s+/g, ' ').slice(0, 90));

  // click the Domains nav link (no sensitive keywords -> executes immediately)
  const ck = await call('act', { kind: 'click', ref: "a[href='/domains']" }, 40000);
  console.log('click a[href=/domains]:', ck.err ? 'ERR ' + ck.t.slice(0, 140) : ck.t.slice(0, 140));
  await sleep(2500);

  const after = await call('snapshot', {});
  const fresh = after.t !== before.t && /domains/i.test(after.t) && after.t.length > 200;
  const href = await call('evaluate_in_page', { expression: 'location.href' });
  console.log('snapshot AFTER len=' + after.t.length + ' fresh=' + fresh);
  console.log('href now:', href.t.slice(0, 140));
  console.log(fresh ? '*** A-FIX VERIFIED: snapshot reflects post-click navigation ***' : '*** STILL STALE ***');
  try { const tabId = JSON.parse(t.t).tabId; await call('tabs', { action: 'close', tabId }); } catch (e) {}
})().catch((e) => console.log('FATAL', e.message));
