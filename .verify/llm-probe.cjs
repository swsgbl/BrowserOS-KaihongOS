// Host-side LLM tool-call probe: minimal output
const MODEL = process.argv[2] || 'qwen38:latest';
const body = JSON.stringify({
  model: MODEL,
  messages: [
    { role: 'system', content: 'You are a browser agent. Use tools.' },
    { role: 'user', content: 'Open https://example.com and tell me the title' }
  ],
  tools: [{ type: 'function', function: { name: 'navigate', description: 'Navigate the webview to a URL', parameters: { type: 'object', properties: { url: { type: 'string', description: 'The URL' } }, required: ['url'] } } }],
  tool_choice: 'auto',
  stream: false
});
const t0 = Date.now();
fetch('http://127.0.0.1:11436/v1/chat/completions', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body })
  .then(r => r.json())
  .then(j => {
    const c = j.choices && j.choices[0];
    const msg = c && c.message || {};
    const tc = msg.tool_calls || [];
    console.log(`MODEL=${MODEL} ms=${Date.now() - t0}`);
    console.log(`finish=${c && c.finish_reason} toolCalls=${tc.length}${tc.map(t => ' ' + t.function.name).join('')}`);
    console.log(`contentHead=${(msg.content || '').replace(/\n/g, ' ').slice(0, 120)}`);
  })
  .catch(e => console.log('ERR', e.message));
