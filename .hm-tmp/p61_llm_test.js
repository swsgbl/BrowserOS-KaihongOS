// P61 step1c: VM -> HOST relay -> agnes LLM round-trip test (native http)
const http = require('http');
const body = JSON.stringify({
  model: 'agnes-3.0-flash',
  messages: [{ role: 'user', content: '回复两个字：成功' }],
  max_tokens: 20,
});
const req = http.request({
  host: '192.168.161.1', port: 19223, path: '/v1/chat/completions', method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
    Authorization: 'Bearer sk-ZzeLuzxw4AgkL90FF7QUSgYoL8DNG1Z2Kt3kHpiKJjOgTHdt',
  },
  timeout: 30000,
}, (res) => {
  let data = '';
  res.on('data', (c) => (data += c));
  res.on('end', () => {
    console.log('LLM_STATUS:', res.statusCode);
    try {
      const j = JSON.parse(data);
      console.log('LLM_REPLY:', j.choices && j.choices[0].message.content);
    } catch (e) {
      console.log('LLM_RAW:', data.slice(0, 300));
    }
  });
});
req.on('error', (e) => console.log('LLM_FAIL:', e.message));
req.on('timeout', () => { req.destroy(); console.log('LLM_FAIL: timeout'); });
req.write(body);
req.end();
