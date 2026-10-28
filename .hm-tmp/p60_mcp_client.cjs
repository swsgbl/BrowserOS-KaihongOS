#!/bin/node
// P60: hmharness 作为真实 MCP 客户端驱动深开鸿浏览器
// 用法: node p60_mcp_client.cjs <脚本步骤JSON文件> <输出日志文件>
const MCP_URL = 'http://127.0.0.1:19222/mcp?token=' + process.env.MCP_TOKEN;
const fs = require('fs');

const scriptFile = process.argv[2];
const outFile = process.argv[3];
const script = JSON.parse(fs.readFileSync(scriptFile, 'utf8'));
const log = [];
let SESSION_ID = null;
function logLine(kind, data) {
  const entry = { t: new Date().toISOString(), kind, data };
  log.push(entry);
  console.error(`[${entry.t}] ${kind}: ${typeof data === 'string' ? data : JSON.stringify(data).slice(0, 200)}`);
}

async function rpc(method, params, id) {
  const body = { jsonrpc: '2.0', method, params };
  if (id !== undefined) body.id = id;
  const headers = { 'Content-Type': 'application/json' };
  if (SESSION_ID) headers['Mcp-Session-Id'] = SESSION_ID;
  const res = await fetch(MCP_URL, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  const sid = res.headers.get('mcp-session-id');
  if (sid) { SESSION_ID = sid; logLine('session_id', sid); }
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch (e) { logLine('parse_error', { text: text.slice(0, 500) }); }
  return { status: res.status, json };
}

(async () => {
  // Step 1: initialize
  logLine('initialize_req', { url: MCP_URL.replace(/token=.*/, 'token=***') });
  const init = await rpc('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'hmharness-p60', version: '1.0.0' },
  }, 1);
  logLine('initialize_res', init.json);
  if (!init.json || !init.json.result) { console.log('INIT FAILED'); process.exit(1); }
  await rpc('notifications/initialized', undefined, undefined);

  // Step 2: tools/list
  const list = await rpc('tools/list', {}, 2);
  const toolNames = (list.json && list.json.result && list.json.result.tools || []).map(t => t.name);
  logLine('tools_list', toolNames);

  let id = 3;
  for (const step of script) {
    const name = step.tool;
    const args = step.args || {};
    logLine(`call:${name}`, args);
    const res = await rpc('tools/call', { name, arguments: args }, id++);
    const resultText = res.json && res.json.result;
    let brief = resultText;
    try {
      const arr = resultText.content || [];
      brief = arr.map(c => c.text || '').join('\n');
    } catch (e) { /* keep raw */ }
    logLine(`result:${name}`, typeof brief === 'string' ? brief.slice(0, 4000) : brief);
    if (res.json && res.json.error) {
      logLine('rpc_error', res.json.error);
    }
    if (step.expect && typeof brief === 'string') {
      const hit = step.expect.some(k => brief.toLowerCase().includes(k.toLowerCase()));
      logLine(`assert:${name}`, { expect: step.expect, pass: hit });
    }
  }
  fs.writeFileSync(outFile, JSON.stringify(log, null, 2));
  console.log('DONE. Log written to ' + outFile);
})().catch(e => {
  logLine('fatal', String(e));
  fs.writeFileSync(outFile, JSON.stringify(log, null, 2));
  console.log('FATAL: ' + e.message);
  process.exit(1);
});
