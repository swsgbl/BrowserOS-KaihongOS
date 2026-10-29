// MCP client for BrowserOS using node native http (no fetch)
const http = require('http');
const fs = require('fs');

const TOKEN = '3738QY2C7JgdSV6os40ODFtUYkswmnpA';
const HOST = '127.0.0.1';
const PORT = 9222;
const PATH = `/mcp?token=${TOKEN}`;
const LOG = '/data/local/tmp/p66_hmh_browser_log.json';

let sessionId = null;
let nextId = 1;

function post(body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'Content-Length': Buffer.byteLength(data)
    };
    if (sessionId) headers['Mcp-Session-Id'] = sessionId;

    const req = http.request(
      { host: HOST, port: PORT, path: PATH, method: 'POST', headers },
      (res) => {
        const sid = res.headers['mcp-session-id'];
        if (sid) sessionId = sid;
        let buf = '';
        res.setEncoding('utf8');
        res.on('data', (c) => { buf += c; });
        res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: buf }));
      }
    );
    req.on('error', reject);
    req.setTimeout(60000, () => { req.destroy(new Error('timeout')); });
    req.write(data);
    req.end();
  });
}

// MCP over streamable http may answer with SSE; extract the JSON-RPC message
function parseResponse(raw) {
  const ct = String(raw.headers['content-type'] || '');
  if (ct.includes('text/event-stream')) {
    for (const line of raw.body.split(/\r?\n/)) {
      if (line.startsWith('data:')) {
        const payload = line.slice(5).trim();
        if (payload) {
          try { return JSON.parse(payload); } catch (e) {}
        }
      }
    }
    return null;
  }
  try { return JSON.parse(raw.body); } catch (e) { return null; }
}

function appendLog(entry) {
  fs.appendFileSync(LOG, JSON.stringify(entry, null, 2) + '\n');
}

async function call(method, params, hasId = true) {
  const body = hasId
    ? { jsonrpc: '2.0', id: nextId++, method, params: params || {} }
    : { jsonrpc: '2.0', method, params: params || {} };
  const raw = await post(body);
  const msg = parseResponse(raw);
  const entry = { step: method, request: body, httpStatus: raw.status, response: msg, rawBody: msg ? undefined : raw.body };
  appendLog(entry);
  console.log(`=== ${method} -> HTTP ${raw.status} ===`);
  console.log(JSON.stringify(msg, null, 2));
  return msg;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  try {
    // 1. initialize
    await call('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: { name: 'hmh-mcp-client', version: '1.0.0' }
    });
    console.log('session id:', sessionId);

    // 2. notifications/initialized (no id, no response expected)
    const notifRaw = await post({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} });
    appendLog({ step: 'notifications/initialized', httpStatus: notifRaw.status, response: null });

    // 3. tools/call tabs new
    await call('tools/call', { name: 'tabs', arguments: { action: 'new', url: 'https://example.com' } });

    // 4. wait 3s
    await sleep(3000);

    // 5. tools/call read
    await call('tools/call', { name: 'read', arguments: {} });

    // extra: list tools, then get page title (snapshot didn't include <title>)
    await call('tools/list', {});
    await call('tools/call', { name: 'tabs', arguments: { action: 'list' } });

    console.log('DONE. log at', LOG);
  } catch (e) {
    console.error('FAILED:', e.message);
    appendLog({ step: 'error', error: String(e) });
    process.exit(1);
  }
})();
