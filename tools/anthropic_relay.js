// anthropic_relay.js — Anthropic-protocol → OpenAI-protocol translating relay.
// Lets Anthropic-protocol clients (Claude Code) use OpenAI-compatible backends
// (GLM coding endpoint, agnes, deepseek, ...).
//   listens :19224  (all hosts — VM reaches via VMware NAT gateway 192.168.161.1)
//   backend from HOST ~/.hmharness/config.json provider block, env overrides:
//     BACKEND_URL / BACKEND_KEY / BACKEND_MODEL
// supports: /v1/messages (+?beta), /v1/messages/count_tokens, tools both ways,
// SSE streaming (buffers backend stream, emits valid Anthropic event sequence).
const http = require('http');
const https = require('https');
const fs = require('fs');

const PORT = 19224;

function backendConfig() {
  let url = process.env.BACKEND_URL;
  let key = process.env.BACKEND_KEY;
  let model = process.env.BACKEND_MODEL;
  if (!url || !key) {
    try {
      const cfg = JSON.parse(fs.readFileSync(require('os').homedir() + '/.hmharness/config.json', 'utf8'));
      const p = cfg.provider || {};
      url = url || p.baseUrl;
      key = key || p.apiKey;
      model = model || p.model;
    } catch (e) { /* env only */ }
  }
  return { url: url || '', key: key || '', model: model || 'glm-5.3' };
}

// ---------- Anthropic request -> OpenAI request ----------
function toOpenAI(body, model) {
  const out = { model, stream: !!body.stream, messages: [] };
  if (body.max_tokens) out.max_tokens = body.max_tokens;
  if (typeof body.temperature === 'number') out.temperature = body.temperature;
  if (body.top_p) out.top_p = body.top_p;
  if (body.stop_sequences && body.stop_sequences.length) out.stop = body.stop_sequences;
  // system
  if (body.system) {
    const sys = typeof body.system === 'string' ? body.system
      : (Array.isArray(body.system) ? body.system.map((b) => b.text || '').join('\n') : '');
    out.messages.push({ role: 'system', content: sys });
  }
  // tools
  if (Array.isArray(body.tools) && body.tools.length) {
    out.tools = body.tools.map((t) => ({ type: 'function', function: { name: t.name, description: t.description || '', parameters: t.input_schema || { type: 'object' } } }));
  }
  if (body.tool_choice && typeof body.tool_choice === 'object' && body.tool_choice.name) {
    out.tool_choice = { type: 'function', function: { name: body.tool_choice.name } };
  }
  for (const m of body.messages || []) {
    const blocks = Array.isArray(m.content) ? m.content : [{ type: 'text', text: String(m.content || '') }];
    if (m.role === 'assistant') {
      let text = '';
      const toolCalls = [];
      for (const b of blocks) {
        if (b.type === 'text') text += b.text || '';
        else if (b.type === 'tool_use') toolCalls.push({ id: b.id, type: 'function', function: { name: b.name, arguments: JSON.stringify(b.input || {}) } });
      }
      out.messages.push({ role: 'assistant', content: text || null, ...(toolCalls.length ? { tool_calls: toolCalls } : {}) });
    } else {
      // user: text blocks + tool_result blocks
      const texts = [];
      for (const b of blocks) {
        if (b.type === 'tool_result') {
          const content = typeof b.content === 'string' ? b.content : Array.isArray(b.content) ? b.content.map((c) => c.text || '').join('\n') : '';
          out.messages.push({ role: 'tool', tool_call_id: b.tool_use_id, content: content || '(empty)' });
        } else if (b.type === 'text' && b.text) {
          texts.push(b.text);
        } else if (b.type === 'image') {
          texts.push('[image omitted]');
        }
      }
      if (texts.length) out.messages.push({ role: 'user', content: texts.join('\n') });
    }
  }
  return out;
}

// ---------- OpenAI response -> Anthropic response ----------
function fromOpenAIMessage(msg, finishReason, usage, id) {
  const content = [];
  const text = msg && msg.content;
  if (typeof text === 'string' && text) content.push({ type: 'text', text });
  if (Array.isArray(msg && msg.tool_calls)) {
    for (const tc of msg.tool_calls) {
      let input = {};
      try { input = JSON.parse(tc.function.arguments || '{}'); } catch (e) { input = {}; }
      content.push({ type: 'tool_use', id: tc.id || ('toolu_' + Math.random().toString(36).slice(2)), name: tc.function.name, input });
    }
  }
  const stop = finishReason === 'tool_calls' ? 'tool_use' : finishReason === 'length' ? 'max_tokens' : 'end_turn';
  return {
    id: id || ('msg_relay_' + Date.now()),
    type: 'message',
    role: 'assistant',
    model: 'relay',
    content: content.length ? content : [{ type: 'text', text: '' }],
    stop_reason: stop,
    stop_sequence: null,
    usage: { input_tokens: (usage && usage.prompt_tokens) || 0, output_tokens: (usage && usage.completion_tokens) || 0 },
  };
}

function anthropicSSE(res, finalMsg) {
  const send = (event, data) => res.write('event: ' + event + '\ndata: ' + JSON.stringify(data) + '\n\n');
  send('message_start', { type: 'message_start', message: { id: finalMsg.id, type: 'message', role: 'assistant', model: finalMsg.model, content: [], stop_reason: null, stop_sequence: null, usage: { input_tokens: finalMsg.usage.input_tokens, output_tokens: 0 } } });
  finalMsg.content.forEach((block, index) => {
    if (block.type === 'text') {
      send('content_block_start', { type: 'content_block_start', index, content_block: { type: 'text', text: '' } });
      send('content_block_delta', { type: 'content_block_delta', index, delta: { type: 'text_delta', text: block.text } });
      send('content_block_stop', { type: 'content_block_stop', index });
    } else if (block.type === 'tool_use') {
      send('content_block_start', { type: 'content_block_start', index, content_block: { type: 'tool_use', id: block.id, name: block.name, input: {} } });
      send('content_block_delta', { type: 'content_block_delta', index, delta: { type: 'input_json_delta', partial_json: JSON.stringify(block.input) } });
      send('content_block_stop', { type: 'content_block_stop', index });
    }
  });
  send('message_delta', { type: 'message_delta', delta: { stop_reason: finalMsg.stop_reason, stop_sequence: null }, usage: { output_tokens: finalMsg.usage.output_tokens } });
  send('message_stop', { type: 'message_stop' });
  send('ping', { type: 'ping' });
}

// ---------- backend call ----------
function callBackend(openaiBody, cb) {
  const be = backendConfig();
  if (!be.url || !be.key) return cb(new Error('relay backend not configured'));
  const u = new URL(be.url.replace(/\/$/, '') + '/chat/completions');
  const data = JSON.stringify(openaiBody);
  const mod = u.protocol === 'https:' ? https : http;
  const req = mod.request({
    hostname: u.hostname, port: u.port || (u.protocol === 'https:' ? 443 : 80),
    path: u.pathname, method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data), Authorization: 'Bearer ' + be.key },
    timeout: 300000,
  }, (res) => {
    const chunks = [];
    res.on('data', (c) => chunks.push(c));
    res.on('end', () => cb(null, { status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
  });
  req.on('error', (e) => cb(e));
  req.on('timeout', () => { req.destroy(); cb(new Error('backend timeout')); });
  req.write(data);
  req.end();
}

const server = http.createServer((req, res) => {
  // optional shared-secret gate: active only when RELAY_TOKEN is set (LAN exposure guard)
  if (process.env.RELAY_TOKEN) {
    const auth = (req.headers['authorization'] || '') + ' ' + (req.headers['x-api-key'] || '') + ' ' + req.url;
    if (!auth.includes(process.env.RELAY_TOKEN)) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ type: 'error', error: { type: 'authentication_error', message: 'relay token required' } }));
      return;
    }
  }
  if (req.method === 'GET' && req.url.startsWith('/health')) {
    const be = backendConfig();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', backend: be.url, model: be.model, hasKey: !!be.key }));
    return;
  }
  if (req.method !== 'POST') { res.writeHead(405); res.end(); return; }
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    let body = null;
    try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch (e) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ type: 'error', error: { type: 'invalid_request_error', message: 'bad json' } }));
      return;
    }
    if (req.url.includes('count_tokens')) {
      const n = JSON.stringify(body).length / 4 | 0;
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ input_tokens: n }));
      return;
    }
    const be = backendConfig();
    const oa = toOpenAI(body, be.model);
    const wantStream = !!body.stream;
    if (wantStream) oa.stream = false; // buffer backend, synthesize Anthropic SSE
    callBackend(oa, (err, r) => {
      if (err) {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ type: 'error', error: { type: 'api_error', message: 'relay: ' + err.message } }));
        return;
      }
      let j = null;
      try { j = JSON.parse(r.body); } catch (e) {}
      if (r.status !== 200 || !j || !j.choices) {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ type: 'error', error: { type: 'api_error', message: 'backend ' + r.status + ': ' + r.body.slice(0, 300) } }));
        return;
      }
      const finalMsg = fromOpenAIMessage(j.choices[0].message, j.choices[0].finish_reason, j.usage, j.id);
      if (wantStream) {
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
        anthropicSSE(res, finalMsg);
        res.end();
      } else {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(finalMsg));
      }
    });
  });
});
server.listen(PORT, '0.0.0.0', () => {
  const be = backendConfig();
  console.log('[anthropic_relay] :%d -> %s (model %s, key %s)', PORT, be.url || '(unset)', be.model, be.key ? 'loaded' : 'MISSING');
});
