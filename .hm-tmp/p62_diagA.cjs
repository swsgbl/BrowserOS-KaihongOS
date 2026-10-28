// P62 probe-A diagnosis: step-by-step labeled calls to find what hangs
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
    const t0 = Date.now();
    const req = http.request({ hostname: u.hostname, port: u.port, path: u.pathname + u.search, method: 'POST', headers, timeout: timeoutMs }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        const sid = res.headers['mcp-session-id'];
        if (sid) SESSION = sid;
        let json = null;
        try { json = JSON.parse(data); } catch (e) { /* raw */ }
        resolve({ status: res.statusCode, json, text: data, ms: Date.now() - t0 });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout-' + timeoutMs)); });
    req.write(body);
    req.end();
  });
}

async function rpc(method, params, withId = true, timeoutMs = 45000) {
  const body = { jsonrpc: '2.0', method };
  if (withId) body.id = id++;
  if (params !== undefined) body.params = params;
  return post(body, timeoutMs);
}
async function call(name, args, timeoutMs = 45000) {
  const r = await rpc('tools/call', { name, arguments: args }, true, timeoutMs);
  if (r.json && r.json.error) return { isError: true, text: 'rpc-error: ' + JSON.stringify(r.json.error), ms: r.ms };
  const res = r.json && r.json.result;
  const text = Array.isArray(res && res.content) ? res.content.map((c) => c.text || '').join('\n') : JSON.stringify(res);
  return { isError: !!(res && res.isError), text, ms: r.ms };
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const init = await rpc('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'p62-diag', version: '1.0.0' } });
  await rpc('notifications/initialized', undefined, false);
  console.log('STEP init ok session=' + SESSION);

  const t = await call('tabs', { action: 'new', url: 'https://www.baidu.com' });
  console.log('STEP tabs.new baidu (' + t.ms + 'ms): ' + t.text.slice(0, 100));
  await sleep(4000);

  const s1 = await call('snapshot', {});
  console.log('STEP snapshot#1 (' + s1.ms + 'ms) len=' + s1.text.length + ': ' + s1.text.replace(/\s+/g, ' ').slice(0, 100));

  const ty = await call('act', { kind: 'type_at', ref: "input[name='wd']", text: 'harmonyos', clear: true });
  console.log('STEP act.type_at (' + ty.ms + 'ms): ' + ty.text.slice(0, 100));

  const ck = await call('act', { kind: 'click', ref: "input[type='submit']" }, 90000);
  console.log('STEP act.click (' + ck.ms + 'ms): ' + ck.text.slice(0, 100));
  await sleep(4000);

  const s2 = await call('snapshot', {});
  console.log('STEP snapshot#2 (' + s2.ms + 'ms) len=' + s2.text.length + ': ' + s2.text.replace(/\s+/g, ' ').slice(0, 100));
  console.log('VERDICT fresh=' + (s1.text !== s2.text && s2.text.length > 200) + ' resultsHit=' + /harmonyos|华为|ArkTS/i.test(s2.text));

  // cleanup: close tab
  try {
    const tabId = JSON.parse(t.text).tabId;
    const cl = await call('tabs', { action: 'close', tabId });
    console.log('STEP close (' + cl.ms + 'ms): ' + cl.text.slice(0, 80));
  } catch (e) { console.log('cleanup skip'); }
})().catch((e) => { console.log('FATAL at: ' + e.message); process.exit(1); });
