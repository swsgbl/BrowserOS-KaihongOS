// v2: also try Authorization Bearer variant + messages endpoint without /v1
const https = require('https');
const fs = require('fs');
const cfg = fs.readFileSync('/data/local/home/.hmharness/config.json', 'utf8');
const key = (cfg.match(/"apiKey": "([^"]+)"/) || [])[1];
const body = JSON.stringify({ model: 'glm-5.3', max_tokens: 20, messages: [{ role: 'user', content: 'hi' }] });
const tries = [
  ['https://open.bigmodel.cn/api/anthropic/v1/messages', { Authorization: 'Bearer ' + key }],
  ['https://open.bigmodel.cn/api/anthropic/v1/messages', { 'x-api-key': key }],
];
let i = 0;
function next() {
  if (i >= tries.length) return;
  const [url, extra] = tries[i++];
  const u = new URL(url);
  const headers = Object.assign({ 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body), 'anthropic-version': '2023-06-01' }, extra);
  const req = https.request({ hostname: u.hostname, path: u.pathname, method: 'POST', headers, timeout: 20000 }, (res) => {
    let d = '';
    res.on('data', (c) => (d += c));
    res.on('end', () => { console.log(Object.keys(extra)[0], '=>', res.statusCode, d.slice(0, 150)); next(); });
  });
  req.on('error', (e) => { console.log(Object.keys(extra)[0], 'ERR', e.message); next(); });
  req.on('timeout', () => { req.destroy(); console.log(Object.keys(extra)[0], 'TIMEOUT'); next(); });
  req.write(body);
  req.end();
}
next();
