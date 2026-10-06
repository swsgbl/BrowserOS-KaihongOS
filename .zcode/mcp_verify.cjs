const TOKEN = 'v9qNClWXHYWUE36iuoNUYrlHXC1a1mAw';
const BASE = 'http://127.0.0.1:9222/mcp';
let session = '';

async function call(method, params, opts = {}) {
  const url = opts.noToken ? BASE : BASE + '?token=' + TOKEN;
  const headers = { 'Content-Type': 'application/json', 'Connection': 'close' };
  if (session && !opts.noSession) headers['Mcp-Session-Id'] = session;
  const body = JSON.stringify({ jsonrpc: '2.0', id: opts.id || 1, method, params: params || {} });
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 12000);
  try {
    const r = await fetch(url, { method: opts.httpMethod || 'POST', headers, body: (opts.httpMethod || 'POST') === 'GET' ? undefined : body, signal: ctl.signal });
    const sid = r.headers.get('mcp-session-id');
    if (sid) session = sid;
    const text = await r.text();
    return { status: r.status, text };
  } finally { clearTimeout(timer); }
}

(async () => {
  const run = async (name, fn) => {
    try {
      const r = await fn();
      console.log(`${r.status} | ${name} | ${r.text.slice(0, 180)}`);
    } catch (e) {
      console.log(`ERR | ${name} | ${e.message}`);
    }
  };
  await run('initialize', () => call('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'zodex', version: '1.0' } }));
  await run('tools/list', () => call('tools/list'));
  await run('tools/call(navigate)', () => call('tools/call', { name: 'navigate', arguments: { url: 'https://example.com' } }, { id: 3 }));
  await run('tools/call(getText)', () => call('tools/call', { name: 'getText', arguments: {} }, { id: 4 }));
  await run('GET /mcp (expect 405)', () => call('x', {}, { httpMethod: 'GET' }));
  await run('no-token (expect 401)', () => call('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'x', version: '1' } }, { noToken: true, id: 9 }));
})();
