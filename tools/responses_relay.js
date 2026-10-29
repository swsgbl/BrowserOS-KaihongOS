// responses_relay.js — OpenAI Responses-protocol → chat-completions translating relay.
// Codex CLI >=0.16x requires wire_api="responses"; GLM coding endpoint only speaks
// chat completions. This bridge lets Codex (on VM) use the GLM backend.
//   listens :19225, handles POST /responses and /v1/responses
//   backend config same as anthropic_relay (HOST ~/.hmharness/config.json / env)
const http = require('http');
const https = require('https');
const fs = require('fs');
const os = require('os');

const PORT = 19225;

function backendConfig() {
  let url = process.env.BACKEND_URL;
  let key = process.env.BACKEND_KEY;
  let model = process.env.BACKEND_MODEL;
  if (!url || !key) {
    try {
      const cfg = JSON.parse(fs.readFileSync(os.homedir() + '/.hmharness/config.json', 'utf8'));
      const p = cfg.provider || {};
      url = url || p.baseUrl;
      key = key || p.apiKey;
      model = model || p.model;
    } catch (e) { /* env only */ }
  }
  return { url: url || '', key: key || '', model: model || 'glm-5.3' };
}

function respText(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) return content.map((c) => c.text || '').join('');
  return '';
}

// Responses request -> chat request
function toChat(body, model) {
  const out = { model, messages: [], stream: false };
  if (body.instructions) out.messages.push({ role: 'system', content: String(body.instructions) });
  if (body.max_output_tokens) out.max_tokens = body.max_output_tokens;
  if (typeof body.temperature === 'number') out.temperature = body.temperature;
  if (body.top_p) out.top_p = body.top_p;
  if (Array.isArray(body.tools) && body.tools.length) {
    out.tools = body.tools.filter((t) => t.type === 'function' || !t.type).map((t) => ({
      type: 'function',
      function: { name: t.name, description: t.description || '', parameters: t.parameters || t.input_schema || { type: 'object' } },
    }));
  }
  if (body.tool_choice && typeof body.tool_choice === 'object' && body.tool_choice.name) {
    out.tool_choice = { type: 'function', function: { name: body.tool_choice.name } };
  }
  const input = body.input;
  const items = typeof input === 'string' ? [{ type: 'message', role: 'user', content: input }] : Array.isArray(input) ? input : [];
  for (const it of items) {
    if (it.type === 'message' || it.role) {
      const text = respText(it.content);
      out.messages.push({ role: it.role === 'assistant' ? 'assistant' : 'user', content: text });
    } else if (it.type === 'function_call') {
      // find previous assistant to attach; simplest: push assistant with tool_calls
      out.messages.push({ role: 'assistant', content: null, tool_calls: [{ id: it.call_id, type: 'function', function: { name: it.name, arguments: it.arguments || '{}' } }] });
    } else if (it.type === 'function_call_output') {
      const o = typeof it.output === 'string' ? it.output : JSON.stringify(it.output || '');
      out.messages.push({ role: 'tool', tool_call_id: it.call_id, content: o || '(empty)' });
    } else if (it.type === 'reasoning') {
      // skip
    }
  }
  return out;
}

// chat response -> Responses response object
function fromChat(j) {
  const choice = j.choices && j.choices[0] || {};
  const msg = choice.message || {};
  const output = [];
  const text = typeof msg.content === 'string' ? msg.content : '';
  if (text) output.push({ type: 'message', id: 'msg_' + Math.random().toString(36).slice(2), role: 'assistant', status: 'completed', content: [{ type: 'output_text', text, annotations: [] }] });
  if (Array.isArray(msg.tool_calls)) {
    for (const tc of msg.tool_calls) {
      output.push({ type: 'function_call', id: 'fc_' + Math.random().toString(36).slice(2), call_id: tc.id || ('call_' + Math.random().toString(36).slice(2)), name: tc.function.name, arguments: tc.function.arguments || '{}', status: 'completed' });
    }
  }
  return {
    id: j.id || ('resp_' + Math.random().toString(36).slice(2)),
    object: 'response',
    created_at: Math.floor(Date.now() / 1000),
    status: 'completed',
    model: j.model || 'relay',
    output,
    usage: {
      input_tokens: (j.usage && j.usage.prompt_tokens) || 0,
      output_tokens: (j.usage && j.usage.completion_tokens) || 0,
      total_tokens: ((j.usage && j.usage.total_tokens) || 0),
    },
    parallel_tool_calls: true,
    tool_choice: 'auto',
    tools: [],
    incomplete_details: null,
    error: null,
    metadata: {},
  };
}

function callBackend(chatBody, cb) {
  const be = backendConfig();
  const u = new URL(be.url.replace(/\/$/, '') + '/chat/completions');
  const data = JSON.stringify(chatBody);
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

function sendSSE(res, resp) {
  const send = (event, data) => res.write('event: ' + event + '\ndata: ' + JSON.stringify(data) + '\n\n');
  send('response.created', { type: 'response.created', response: { id: resp.id, object: 'response', status: 'in_progress', model: resp.model, output: [] } });
  resp.output.forEach((item, idx) => {
    send('response.output_item.added', { type: 'response.output_item.added', output_index: idx, item: { id: item.id, type: item.type, status: 'in_progress' } });
    if (item.type === 'message') {
      // P68: content_part lifecycle silences Codex "OutputTextDelta without active item"
      send('response.content_part.added', { type: 'response.content_part.added', item_id: item.id, output_index: idx, content_index: 0, part: { type: 'output_text', text: '', annotations: [] } });
      send('response.output_text.delta', { type: 'response.output_text.delta', output_index: idx, content_index: 0, delta: item.content[0].text });
      send('response.content_part.done', { type: 'response.content_part.done', item_id: item.id, output_index: idx, content_index: 0, part: { type: 'output_text', text: item.content[0].text, annotations: [] } });
    } else if (item.type === 'function_call') {
      send('response.function_call_arguments.delta', { type: 'response.function_call_arguments.delta', output_index: idx, delta: item.arguments });
    }
    send('response.output_item.done', { type: 'response.output_item.done', output_index: idx, item });
  });
  send('response.completed', { type: 'response.completed', response: resp });
}

const server = http.createServer((req, res) => {
  // optional shared-secret gate (same convention as anthropic_relay)
  if (process.env.RELAY_TOKEN) {
    const auth = (req.headers['authorization'] || '') + ' ' + req.url;
    if (!auth.includes(process.env.RELAY_TOKEN)) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: 'relay token required' } }));
      return;
    }
  }
  if (req.method === 'GET' && req.url.startsWith('/health')) {
    const be = backendConfig();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', backend: be.url, model: be.model }));
    return;
  }
  if (req.method !== 'POST') { res.writeHead(405); res.end(); return; }
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    let body = null;
    try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch (e) {
      res.writeHead(400); res.end(JSON.stringify({ error: { message: 'bad json' } }));
      return;
    }
    const be = backendConfig();
    const chat = toChat(body, be.model);
    callBackend(chat, (err, r) => {
      if (err) { res.writeHead(502); res.end(JSON.stringify({ error: { message: 'relay: ' + err.message } })); return; }
      let j = null;
      try { j = JSON.parse(r.body); } catch (e) {}
      if (r.status !== 200 || !j || !j.choices) {
        res.writeHead(502);
        res.end(JSON.stringify({ error: { message: 'backend ' + r.status + ': ' + r.body.slice(0, 300) } }));
        return;
      }
      const resp = fromChat(j);
      if (body.stream) {
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
        sendSSE(res, resp);
        res.end();
      } else {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(resp));
      }
    });
  });
});
server.listen(PORT, '0.0.0.0', () => {
  const be = backendConfig();
  console.log('[responses_relay] :%d -> %s (model %s)', PORT, be.url, be.model);
});
