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
// P70: default to the app's live token file (root-readable) — rotations are picked up
// automatically by refreshToken(); the /data/local/tmp copy remains a fallback.
const TOKEN_FILE = argOf('--token-file', '/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt');
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

// // P70: app restarts rotate the CSPRNG token; re-read the file on auth failure
// (previously a stale token killed the runner at startup -> device-agent tasks
// hung forever -> "AI 面板没有输出")
function refreshToken() {
  try {
    const t = fs.readFileSync(TOKEN_FILE, 'utf8').trim();
    if (t && t !== TOKEN) {
      TOKEN = t;
      sessionId = null;
      log('token refreshed from file (rotated)');
      return true;
    }
  } catch (e) { /* file briefly absent during app restart */ }
  return false;
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

// ---------- P69: system_update 分支（重启即更） ----------
// 应用投递 kind=system_update 任务（prompt= SYSTEM_UPDATE||path=<sandbox hap>||sha256=..||version=..）
// runner 以 root 执行：校验 hap 存在 → sha256 复核 → bm install -r → aa start（应用被杀重启即新版）。
// 注意：任务对象在 runner 进程内修改 kind 字段后随 complete 回写。
async function runSystemUpdate(task) {
  const parts = String(task.prompt || '').split('||');
  const kv = {};
  for (const p of parts) {
    const i = p.indexOf('=');
    if (i > 0) kv[p.slice(0, i).trim()] = p.slice(i + 1).trim();
  }
  const hapPath = kv.path || '';
  const expectSha = (kv.sha256 || '').toLowerCase();
  const version = kv.version || '?';
  const out = [];
  if (!hapPath || !hapPath.startsWith('/data/app/el2/100/base/com.browseros.kaihong/')) {
    return { ok: false, result: `system_update rejected: bad hap path ${hapPath}` };
  }
  if (!fs.existsSync(hapPath)) {
    return { ok: false, result: `system_update rejected: hap not found ${hapPath}` };
  }
  const crypto = require('crypto');
  const h = crypto.createHash('sha256');
  h.update(fs.readFileSync(hapPath));
  const actual = h.digest('hex');
  out.push(`sha256 ${actual === expectSha ? 'MATCH' : 'MISMATCH'} (${actual.slice(0, 12)}..)`);
  if (actual !== expectSha) {
    return { ok: false, result: out.join('\n') + '\nrejected: sha256 mismatch' };
  }
  const exec = (cmd) => new Promise((resolve) => {
    execFile('/system/bin/sh', ['-c', cmd], { timeout: 120000 }, (err, stdout, stderr) => {
      out.push(`$ ${cmd}\n${(stdout || '') + (stderr || '')}`.trim());
      resolve(err ? (err.code || 1) : 0);
    });
  });
  let code = await exec('bm install -p ' + shellQuote(hapPath) + ' -r');
  if (code !== 0) {
    return { ok: false, result: out.join('\n') + `\nbm install exit ${code}` };
  }
  // 应用此刻已被 bm install -r 杀掉；aa start 拉起新版
  code = await exec('sleep 1 && aa start -a EntryAbility -b com.browseros.kaihong');
  out.push(`system_update v${version} done (aa start exit ${code})`);
  return { ok: true, result: out.join('\n') };
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
  log('claimed task:', task.taskId, 'kind=', task.kind || 'prompt', 'prompt=', String(task.prompt).slice(0, 120));
  let ok = false;
  let result = '';
  if (task.kind === 'system_update') {
    const r = await runSystemUpdate(task);
    ok = r.ok;
    result = r.result;
    log('system_update done:', task.taskId, 'ok=', ok);
  } else {
    const ctx = { url: task.contextUrl, title: task.contextTitle };
    let prompt = String(task.prompt || '');
    if (task.contextUrl) prompt += `\n\n[Context page] ${task.contextTitle || ''} ${task.contextUrl}`;
    const out = await runTemplate(prompt, ctx);
    ok = out.code === 0;
    result = ok ? out.stdout : (out.stderr || out.err || `exit ${out.code}`);
  }
  if (result.length > 32 * 1024) result = result.slice(0, 32 * 1024) + '…';
  log('task done:', task.taskId, 'ok=', ok, 'len=', result.length);
  await toolCall('device_agent_tasks', { action: 'complete', taskId: task.taskId, ok, result });
}

async function main() {
  log(`runner start name=${NAME} kind=${KIND} cmd="${CMD_TEMPLATE.slice(0, 80)}" ${HOST}:${PORT}`);
  // P70: init retry loop — the app may be down/restarting or the token just rotated
  for (;;) {
    try {
      refreshToken();
      await call('initialize', {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: `da-runner-${NAME}`, version: '1.0.0' }
      });
      break;
    } catch (e) {
      log('init retry (app down or token rotated):', String(e.message || e).slice(0, 120));
      await sleep(5000);
    }
  }
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
      // 会话失效时重初始化（P70: 先尝试刷新已轮换的 token）
      try {
        refreshToken();
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
