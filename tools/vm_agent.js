#!/usr/bin/env node
// P61: VM 内驻 AI Agent —— 运行在 KaihongOS 虚拟机上，通过本机 MCP 直连驱动 BrowserOS 浏览器。
//
// 架构（全部运行在 VM 内，本脚本即 "AI agent"）：
//   LLM 决策: http://192.168.161.1:19223/v1/chat/completions  (HOST 中继 -> apihub.agnes-ai.com)
//   工具执行: http://127.0.0.1:9222/mcp?token=<sandbox token>  (BrowserOS MCP, loopback)
//
// 用法: node vm_agent.js "<任务描述>" [日志输出路径]
// 注意: VM 的 Node.js 全局 fetch 不可用 (WebAssembly undefined)，全程用原生 http 模块。

const http = require('http');
const fs = require('fs');

// ---------- 配置 ----------
const HOST_RELAY = '192.168.161.1';
const RELAY_PORT = 19223;
const MCP_HOST = '127.0.0.1';
const MCP_PORT = 9222;
const TOKEN_PATH = '/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt';
const LLM_KEY = 'sk-ZzeLuzxw4AgkL90FF7QUSgYoL8DNG1Z2Kt3kHpiKJjOgTHdt';
const LLM_MODEL = 'agnes-3.0-flash';
const MAX_STEPS = 12;
const LLM_TIMEOUT_MS = 60000;
const MCP_TIMEOUT_MS = 30000;

const TASK = process.argv[2] || '打开 https://example.com 并告诉我页面标题和第一段内容';
const LOG_OUT = process.argv[3] || '/data/local/tmp/p61_agent_log.json';

// ---------- 基础 HTTP（原生模块） ----------
function postJson(host, port, path, headers, bodyObj, timeoutMs) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(bodyObj);
    const h = Object.assign({ 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }, headers);
    const req = http.request({ host, port, path, method: 'POST', headers: h, timeout: timeoutMs }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        let json = null;
        try { json = JSON.parse(data); } catch (e) { /* keep raw */ }
        resolve({ status: res.statusCode, headers: res.headers, text: data, json });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout after ' + timeoutMs + 'ms')); });
    req.write(body);
    req.end();
  });
}

// ---------- 日志 ----------
const LOG = [];
function log(kind, data) {
  const entry = { t: new Date().toISOString(), kind, data };
  LOG.push(entry);
  const brief = typeof data === 'string' ? data : JSON.stringify(data);
  console.log(`[${entry.t}] ${kind}: ${brief.length > 300 ? brief.slice(0, 300) + '…(' + brief.length + 'B)' : brief}`);
}
function flushLog() {
  try { fs.writeFileSync(LOG_OUT, JSON.stringify(LOG, null, 2)); } catch (e) { console.log('log write fail: ' + e.message); }
}

// ---------- MCP 客户端 ----------
let MCP_TOKEN = '';
let SESSION_ID = null;
let rpcId = 1;

function readToken() {
  const t = fs.readFileSync(TOKEN_PATH, 'utf8').trim();
  if (!t) throw new Error('empty MCP token at ' + TOKEN_PATH);
  return t;
}

async function mcpRpc(method, params, withId) {
  const body = { jsonrpc: '2.0', method };
  if (withId) body.id = rpcId++;
  if (params !== undefined) body.params = params;
  const headers = {};
  if (SESSION_ID) headers['Mcp-Session-Id'] = SESSION_ID;
  const res = await postJson(MCP_HOST, MCP_PORT, '/mcp?token=' + encodeURIComponent(MCP_TOKEN), headers, body, MCP_TIMEOUT_MS);
  const sid = res.headers['mcp-session-id'];
  if (sid) SESSION_ID = sid;
  return res;
}

async function mcpCallTool(name, args) {
  const res = await mcpRpc('tools/call', { name, arguments: args }, true);
  if (res.json && res.json.error) {
    return { isError: true, text: 'MCP error ' + JSON.stringify(res.json.error) };
  }
  const r = res.json && res.json.result;
  if (!r) return { isError: true, text: 'MCP empty result, http ' + res.status + ', body: ' + res.text.slice(0, 200) };
  const text = Array.isArray(r.content) ? r.content.map((c) => c.text || '').join('\n') : JSON.stringify(r);
  return { isError: !!r.isError, text: text.slice(0, 12000) };
}

// ---------- LLM 客户端（经 HOST 中继） ----------
async function llmChat(messages) {
  const res = await postJson(HOST_RELAY, RELAY_PORT, '/v1/chat/completions', {
    Authorization: 'Bearer ' + LLM_KEY,
  }, {
    model: LLM_MODEL,
    messages,
    temperature: 0.2,
    max_tokens: 2000,
  }, LLM_TIMEOUT_MS);
  if (res.status !== 200 || !res.json || !res.json.choices) {
    throw new Error('LLM http ' + res.status + ' body: ' + res.text.slice(0, 300));
  }
  return res.json.choices[0].message;
}

// ---------- 工具调用解析（双协议：原生 tool_calls + 文本 JSON 兜底） ----------
function parseToolCallFromText(content) {
  if (!content) return null;
  const m = content.match(/\{[\s\S]*\}/);
  if (!m) return null;
  try {
    const obj = JSON.parse(m[0]);
    const tc = obj.tool_call || obj.toolcall || obj.tool;
    if (tc && tc.name) return { name: tc.name, arguments: tc.arguments || {} };
  } catch (e) { /* not JSON */ }
  return null;
}

// ---------- Agent 主循环 ----------
(async () => {
  log('agent_start', { task: TASK, model: LLM_MODEL, mcp: `${MCP_HOST}:${MCP_PORT}`, relay: `${HOST_RELAY}:${RELAY_PORT}` });

  // 1. 读 token + MCP initialize
  MCP_TOKEN = readToken();
  log('mcp_token', 'loaded (' + MCP_TOKEN.length + ' chars)');
  const init = await mcpRpc('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'vm-agent-p61', version: '1.0.0' },
  }, true);
  log('mcp_initialize', { status: init.status, sessionId: SESSION_ID, serverInfo: init.json && init.json.result && init.json.result.serverInfo });
  if (!init.json || !init.json.result) { log('fatal', 'initialize failed: ' + init.text.slice(0, 300)); flushLog(); process.exit(1); }
  await mcpRpc('notifications/initialized', undefined, false);

  // 2. tools/list
  const list = await mcpRpc('tools/list', {}, true);
  const tools = (list.json && list.json.result && list.json.result.tools) || [];
  log('mcp_tools', tools.map((t) => t.name).join(','));

  const toolCatalog = tools.map((t) => `- ${t.name}: ${t.description || ''} schema=${JSON.stringify(t.inputSchema || {})}`).join('\n');

  // 3. 对话循环
  const SYSTEM_PROMPT =
    '你是一个运行在 KaihongOS 设备上的浏览器自动化 AI agent。你可以通过 MCP 工具控制本机 BrowserOS 浏览器。\n' +
    '可用工具列表（name + schema）：\n' + toolCatalog + '\n\n' +
    '调用工具时，只回复一个 JSON 对象（不要加其他文字、不要用 markdown 代码块）：\n' +
    '{"tool_call": {"name": "工具名", "arguments": {...}}}\n' +
    '拿到足够信息、完成任务后，用纯文本（非 JSON）给出最终答案。答案用中文。\n' +
    '标签页用完后请关闭自己创建的标签页（tabs close）。';

  const messages = [
    { role: 'system', content: SYSTEM_PROMPT },
    { role: 'user', content: TASK },
  ];

  let finalAnswer = null;
  for (let step = 1; step <= MAX_STEPS; step++) {
    log('llm_request', 'step ' + step + ', messages=' + messages.length);
    let msg;
    try {
      msg = await llmChat(messages);
    } catch (e) {
      log('llm_error', e.message);
      break;
    }
    const content = msg.content || '';

    let calls = [];
    if (Array.isArray(msg.tool_calls) && msg.tool_calls.length) {
      // 原生 tool_calls 协议
      calls = msg.tool_calls.map((tc) => {
        let args = {};
        try { args = JSON.parse(tc.function.arguments || '{}'); } catch (e) { /* empty */ }
        return { id: tc.id, name: tc.function.name, arguments: args };
      });
      messages.push({ role: 'assistant', content: content, tool_calls: msg.tool_calls });
    } else {
      const tc = parseToolCallFromText(content);
      if (tc) {
        calls = [Object.assign({ id: 'fallback-0' }, tc)];
        messages.push({ role: 'assistant', content: content });
      } else {
        finalAnswer = content;
        log('final_answer', content);
        break;
      }
    }

    for (const call of calls) {
      log('tool_exec', { name: call.name, arguments: call.arguments });
      let result;
      try {
        result = await mcpCallTool(call.name, call.arguments);
      } catch (e) {
        result = { isError: true, text: 'tool transport error: ' + e.message };
      }
      log('tool_result', { name: call.name, isError: result.isError, text: result.text.slice(0, 1500) });
      if (Array.isArray(msg.tool_calls) && msg.tool_calls.length) {
        messages.push({ role: 'tool', tool_call_id: call.id, content: result.text.slice(0, 8000) });
      } else {
        messages.push({ role: 'user', content: '工具 ' + call.name + ' 执行结果：\n' + result.text.slice(0, 8000) + '\n\n继续。若已足够回答，请给最终答案（纯文本）。' });
      }
    }
  }

  if (!finalAnswer) finalAnswer = '(达到步数上限或出错，未获得最终答案；见日志)';
  log('agent_done', { task: TASK, answer: finalAnswer });
  flushLog();
  console.log('\n===== 最终答案 =====\n' + finalAnswer);
})().catch((e) => {
  log('fatal', String(e && e.stack || e));
  flushLog();
  process.exit(1);
});
