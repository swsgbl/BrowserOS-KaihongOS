#!/bin/node
// P62 acceptance probes: reproduce/verify defects via direct MCP calls (no LLM quota needed).
// Probes:
//   E: unknown method (server/discover) -> -32601
//   B: session isolation of implicit read target (two sessions; S1 read must return S1-owned tab, NOT S2's active tab)
//   A: act-driven navigation must refresh snapshot (content changes after click-submit)
//   C: history back returns structured body (url), forward works
//   D: grep hits visible text on IANA page
// Usage: node tools/p62_verify.cjs <mcp-url-with-token>   (host fport or VM loopback both fine)
// Exit 0 = all PASS.

const MCP_URL = process.argv[2];
if (!MCP_URL || !MCP_URL.startsWith('http')) {
  console.error('usage: node p62_verify.cjs <mcp-url-with-token>');
  process.exit(2);
}
const results = [];

function record(name, pass, detail) {
  results.push({ name, pass });
  console.log((pass ? 'PASS' : 'FAIL') + ' [' + name + '] ' + String(detail).replace(/\s+/g, ' ').slice(0, 260));
}

const http = require('http');
const https = require('https');
const { URL } = require('url');

function makeClient() {
  const state = { session: null, id: 1 };
  function post(bodyObj, timeoutMs) {
    return new Promise((resolve, reject) => {
      const u = new URL(MCP_URL);
      const lib = u.protocol === 'https:' ? https : http;
      const body = JSON.stringify(bodyObj);
      const headers = { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) };
      if (state.session) headers['Mcp-Session-Id'] = state.session;
      const req = lib.request({ hostname: u.hostname, port: u.port, path: u.pathname + u.search, method: 'POST', headers, timeout: timeoutMs }, (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          const sid = res.headers['mcp-session-id'];
          if (sid) state.session = sid;
          let json = null;
          try { json = JSON.parse(data); } catch (e) { /* raw */ }
          resolve({ status: res.statusCode, json, text: data });
        });
      });
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
      req.write(body);
      req.end();
    });
  }
  async function rpc(method, params, withId = true, timeoutMs = 60000) {
    const body = { jsonrpc: '2.0', method };
    if (withId) body.id = state.id++;
    if (params !== undefined) body.params = params;
    return post(body, timeoutMs);
  }
  async function call(name, args, timeoutMs = 60000) {
    const r = await rpc('tools/call', { name, arguments: args }, true, timeoutMs);
    if (r.json && r.json.error) return { isError: true, text: 'rpc-error: ' + JSON.stringify(r.json.error) };
    const res = r.json && r.json.result;
    const text = Array.isArray(res && res.content) ? res.content.map((c) => c.text || '').join('\n') : JSON.stringify(res);
    return { isError: !!(res && res.isError), text };
  }
  return {
    get session() { return state.session; },
    initialize: async (name) => {
      const init = await rpc('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name, version: '1.0.0' } });
      if (!init.json || !init.json.result) throw new Error('initialize failed: ' + init.text.slice(0, 150));
      await rpc('notifications/initialized', undefined, false);
    },
    rpc, call,
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const parseTabId = (t) => { try { return JSON.parse(t.text).tabId; } catch (e) { return null; } };

(async () => {
  // ---- E: unknown method should be -32601
  {
    const c = makeClient();
    await c.initialize('p62-e');
    const r = await c.rpc('server/discover', {}, true);
    const err = r.json && r.json.error;
    record('E-discover-32601', err && err.code === -32601, 'code=' + (err && err.code) + ' msg=' + (err && err.message));
  }

  // ---- B: implicit read target must stay inside the session's owned tabs
  {
    const s1 = makeClient();
    await s1.initialize('p62-b1');
    const t1 = await s1.call('tabs', { action: 'new', url: 'https://example.com' });
    const tabA = parseTabId(t1);
    await sleep(2500);

    const s2 = makeClient();
    await s2.initialize('p62-b2');
    const t2 = await s2.call('tabs', { action: 'new', url: 'https://www.iana.org/domains/reserved' });
    const tabB = parseTabId(t2);
    await sleep(3000);
    // s2 activates its tab so the GLOBAL active tab is now B (foreign to s1)
    await s2.call('tabs', { action: 'activate', tabId: tabB });
    await sleep(500);

    // s1 read WITHOUT tabId: must return A content (session-owned), not B and not null
    const rd = await s1.call('read', {});
    const gotA = /documentation examples|文档示例|example\.com/i.test(rd.text);
    const leakedB = /IANA-managed Reserved Domains/i.test(rd.text);
    const nullBody = /"null"/.test(rd.text) || /^\s*\{\s*"result"\s*:\s*"null"\s*\}\s*$/.test(rd.text);
    record('B-read-session-owned', gotA && !leakedB && !nullBody,
      'tabA=' + tabA + ' tabB=' + tabB + ' read120=' + rd.text.slice(0, 120));

    if (tabA) await s1.call('tabs', { action: 'close', tabId: tabA });
    if (tabB) await s2.call('tabs', { action: 'close', tabId: tabB });
  }

  // ---- A: act-driven navigation must refresh snapshot content
  {
    const c = makeClient();
    await c.initialize('p62-a');
    const t = await c.call('tabs', { action: 'new', url: 'https://www.baidu.com' });
    const tabId = parseTabId(t);
    await sleep(3500);
    const before = await c.call('snapshot', {});
    await c.call('act', { kind: 'type_at', ref: "input[name='wd']", text: 'harmonyos 开发', clear: true });
    const clicked = await c.call('act', { kind: 'click', ref: "input[type='submit']" }, 90000);
    await sleep(4000);
    const after = await c.call('snapshot', {});
    const changed = before.text !== after.text && after.text.length > 200;
    const hasResults = /harmonyos|ArkTS|华为|开发/i.test(after.text);
    record('A-snapshot-fresh-after-act', changed && hasResults,
      'click=' + (clicked.isError ? 'ERR ' + clicked.text.slice(0, 80) : 'ok') + ' len ' + before.text.length + '->' + after.text.length + ' resultsHit=' + hasResults + ' after120=' + after.text.slice(0, 100));
    if (tabId) await c.call('tabs', { action: 'close', tabId });
  }

  // ---- C: history back returns structured body; ---- D: grep hits visible text
  {
    const c = makeClient();
    await c.initialize('p62-c');
    const t = await c.call('tabs', { action: 'new', url: 'https://example.com' });
    const tabId = parseTabId(t);
    await sleep(2500);
    await c.call('navigate', { url: 'https://www.iana.org/domains/reserved' });
    await sleep(3000);
    const back = await c.call('history', { action: 'back' });
    const hasBody = /url|title|example/i.test(back.text) && back.text.trim() !== '{}' && back.text.trim() !== '';
    record('C-history-back-body', hasBody, 'body=' + back.text.slice(0, 140));

    await c.call('history', { action: 'forward' });
    await sleep(2500);
    const g = await c.call('grep', { pattern: 'Reserved' });
    let hits = -1;
    try {
      const j = JSON.parse(g.text);
      const arr = j.matches || j.hits || j.result;
      hits = Array.isArray(arr) ? arr.length : (typeof arr === 'number' ? arr : -1);
    } catch (e) {
      hits = (g.text.match(/Reserved/g) || []).length;
    }
    record('D-grep-hits', hits > 0, 'hits=' + hits + ' raw=' + g.text.slice(0, 140));
    if (tabId) await c.call('tabs', { action: 'close', tabId });
  }

  const pass = results.filter((r) => r.pass).length;
  console.log('\n===== P62 VERIFY: ' + pass + '/' + results.length + ' PASS =====');
  results.filter((r) => !r.pass).forEach((r) => console.log('FAILED: ' + r.name));
  process.exit(pass === results.length ? 0 : 1);
})().catch((e) => { console.log('FATAL:', e.message); process.exit(1); });
