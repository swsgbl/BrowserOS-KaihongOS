#!/usr/bin/env node
/**
 * P67: 设备智能体 runner —— 把 VM 上的 Claude Code / Codex / hmharness 接进
 * BrowserOS 的 AI 切换菜单（收件箱模式）。
 *
 * 架构：应用不能 spawn 子进程 → 应用侧只写任务文件（files/device_agent_tasks/），
 * 本 runner 在 VM 终端常驻：
 *   1. MCP initialize（Mcp-Session-Id + Bearer token）
 *   2. agent_register 注册（每 30s 重注册 = 心跳，UI 在线点 = lastSeen<2min）
 *   3. 循环 device_agent_tasks next 领任务 → 执行命令模板 → complete 回写
 *
 * 用法（VM 内，root/shell 均可）：
 *   node /data/local/tmp/device_agent_runner.js \
 *     --name claude-code --kind claude-code \
 *     --cmd "claude --dangerously-skip-permissions -p {prompt}"
 *
 * token 缺省读 /data/local/tmp/browseros_mcp_token（一行）。
 * {prompt} 会被替换成任务 prompt（单引号安全转义）。
 * 执行超时默认 10min；--timeout-min 可调。结果截断 32KB 回写。
 */
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

// ---------- 参数 ----------
const args = process.argv.slice(2);
function argOf(flag, dflt) {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : dflt;
}
const NAME = argOf('--name', 'claude-code');
const KIND = argOf('--kind', NAME === 'claude-code' ? 'claude-code' : NAME === 'codex' ? 'codex' : NAME === 'hmharness' ? 'hmharness' : 'custom');
const CMD_TEMPLATE = argOf('--cmd', '');
const HOST = argOf('--host', '127.0.0.1');
const PORT = parseInt(argOf('--port', '9222'), 10);
const TOKEN_FILE = argOf('--token-file', '/data/local/tmp/browseros_mcp_token');
const TIMEOUT_MIN = parseFloat(argOf('--timeout-min', '10'));
const POLL_MS = parseInt(argOf('--poll-ms', '3000'), 10);
const LOG = argOf('--log', `/data/local/tmp/da_runner_${NAME}.log`);

let TOKEN = argOf('--token', '');
if (!TOKEN) {
  try {
    TOKEN = fs.readFileSync(TOKEN_FILE, 'utf8').trim();
  } catch (e) {
    console.error(`[runner] cannot read token from ${TOKEN_FILE}; pass --token`);
    process.exit(1);
  }
}

function log(...a) {
  const line = `[${new Date().toISOString()}] ` + a.join(' ');
  console.log(line);
  try { fs.appendFileSync(LOG, line + '\n'); } catch (e) {}
}

// ---------- MCP 客户端（node 原生 http，SSE 容忍） ----------
let sessionId = null;
let nextId = 1;

function post(body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'Content-Length': Buffer.byteLength(data),
      'Authorization': `Bearer ${TOKEN}`
    };
    if (sessionId) headers['Mcp-Session-Id'] = sessionId;
    const req = http.request(
      { host: HOST, port: PORT, path: `/mcp?token=${encodeURIComponent(TOKEN)}`, method: 'POST', headers },
      (res) => {
        const sid = res.headers['mcp-session-id'];
        if (sid) sessionId = sid;
        let buf = '';
        res.setEncoding('utf8');
        res.on('data', (c) => { buf += c; });
        res.on('end', () => resolve({ status: res.statusCode, body: buf }));
      }
    );
    req.on('error', reject);
    req.setTimeout(30000, () => { req.destroy(new Error('mcp timeout')); });
    req.write(data);
    req.end();
  });
}

function parseResponse(raw) {
  const body = typeof raw.body === 'string' ? raw.body : JSON.stringify(raw.body);
  // SSE or plain JSON both fine
  const m = body.match(/(?:^|\n)data:\s*(\{.*\})(?:\n|$)/);
  if (m) {
    try { return JSON.parse(m[1]); } catch (e) {}
  }
  try { return JSON.parse(body); } catch (e) { return null; }
}

async function call(method, params) {
  const body = { jsonrpc: '2.0', id: nextId++, method, params: params || {} };
  const raw = await post(body);
  if (raw.status !== 200) {
    throw new Error(`mcp ${method} http ${raw.status}: ${raw.body.slice(0, 200)}`);
  }
  const msg = parseResponse(raw);
  if (!msg) throw new Error(`mcp ${method} unparseable: ${raw.body.slice(0, 200)}`);
  if (msg.error) throw new Error(`mcp ${method} error: ${JSON.stringify(msg.error)}`);
  return msg.result;
}

/** tools/call 包装：返回 content[0].text 解析后的 data（应用侧 okResponse 结构） */
async function toolCall(name, toolArgs) {
  const result = await call('tools/call', { name, arguments: toolArgs });
  try {
    const text = result.content[0].text;
    return JSON.parse(text);
  } catch (e) {
    return result;
  }
}

// ---------- 命令模板执行 ----------
function shellQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

function runTemplate(prompt, ctx) {
  if (!CMD_TEMPLATE) {
    return Promise.resolve({ code: 0, stdout: `(no --cmd template; prompt was: ${prompt})` });
  }
  let cmdline = CMD_TEMPLATE.replace(/\{prompt\}/g, shellQuote(prompt))
    .replace(/\{url\}/g, shellQuote(ctx.url || ''))
    .replace(/\{title\}/g, shellQuote(ctx.title || ''));
  log('exec:', cmdline.slice(0, 300));
  return new Promise((resolve) => {
    execFile('/system/bin/sh', ['-c', cmdline], { timeout: TIMEOUT_MIN * 60 * 1000, maxBuffer: 16 * 1024 * 1024, env: Object.assign({}, process.env, { IS_SANDBOX: '1' }) }, (err, stdout, stderr) => {
      const code = err ? (err.code || 1) : 0;
      resolve({ code, stdout: stdout || '', stderr: stderr || '', err: err ? String(err.message || err) : '' });
    });
  });
}

// ---------- 主循环 ----------
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function register() {
  const r = await toolCall('agent_register', { name: NAME, kind: KIND });
  log('registered:', JSON.stringify(r));
}

async function pollOnce() {
  const r = await toolCall('device_agent_tasks', { action: 'next', agent: NAME });
  const task = r && r.task;
  if (!task || !task.taskId) {
    return;
  }
  log('claimed task:', task.taskId, 'prompt=', String(task.prompt).slice(0, 120));
  const ctx = { url: task.contextUrl, title: task.contextTitle };
  let prompt = String(task.prompt || '');
  if (task.contextUrl) prompt += `\n\n[Context page] ${task.contextTitle || ''} ${task.contextUrl}`;
  const out = await runTemplate(prompt, ctx);
  const ok = out.code === 0;
  let result = ok ? out.stdout : (out.stderr || out.err || `exit ${out.code}`);
  if (result.length > 32 * 1024) result = result.slice(0, 32 * 1024) + '…';
  log('task done:', task.taskId, 'ok=', ok, 'len=', result.length);
  await toolCall('device_agent_tasks', { action: 'complete', taskId: task.taskId, ok, result });
}

async function main() {
  log(`runner start name=${NAME} kind=${KIND} cmd="${CMD_TEMPLATE.slice(0, 80)}" ${HOST}:${PORT}`);
  await call('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: `da-runner-${NAME}`, version: '1.0.0' }
  });
  log('mcp session:', sessionId);
  await post({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} });

  await register();
  let sinceBeat = 0;
  for (;;) {
    try {
      if (sinceBeat >= 30000) {
        await register();
        sinceBeat = 0;
      }
      await pollOnce();
    } catch (e) {
      log('loop error:', String(e.message || e).slice(0, 300));
      // 会话失效时重初始化
      try {
        sessionId = null;
        await call('initialize', {
          protocolVersion: '2024-11-05', capabilities: {},
          clientInfo: { name: `da-runner-${NAME}`, version: '1.0.0' }
        });
        await post({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} });
        log('re-initialized after error');
      } catch (e2) {
        log('re-init failed:', String(e2.message || e2).slice(0, 200));
      }
      await sleep(5000);
    }
    await sleep(POLL_MS);
    sinceBeat += POLL_MS;
  }
}

main().catch((e) => {
  log('fatal:', String(e));
  process.exit(1);
});
