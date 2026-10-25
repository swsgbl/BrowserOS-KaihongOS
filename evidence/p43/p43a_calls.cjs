const http = require('http');
const fs = require('fs');
const TOKEN = 'zJHOtOF7BY0ZM5cKD4T6tBwjAtGkl7Hy';
const PORT = 19222;

function rpc(method, params, id) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ jsonrpc: '2.0', id: id, method: method, params: params || {} });
    const req = http.request({
      host: '127.0.0.1', port: PORT, path: '/mcp?token=' + TOKEN, method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
    }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, json: JSON.parse(data), raw: data }); }
        catch (e) { resolve({ status: res.statusCode, json: null, raw: data }); }
      });
    });
    req.on('error', reject);
    req.setTimeout(20000, () => { req.destroy(); reject(new Error('timeout')); });
    req.write(body);
    req.end();
  });
}

let nextId = 10;
function callTool(name, args) {
  return rpc('tools/call', { name: name, arguments: args }, nextId++);
}

(async () => {
  const results = [];
  function record(name, verdict, detail) {
    results.push({ tool: name, verdict: verdict, detail: detail });
    console.log('[' + verdict + '] ' + name + ': ' + detail);
  }

  // 1) tabs list
  let r = await callTool('tabs', { action: 'list' });
  let txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  let pass = r.json && r.json.result && !r.json.error && txt.includes('tabs');
  record('tabs list', pass ? 'PASS' : 'FAIL', txt.substring(0, 150).replace(/\n/g, ' '));

  // 2) tabs active
  r = await callTool('tabs', { action: 'active' });
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = r.json && r.json.result && !r.json.error;
  record('tabs active', pass ? 'PASS' : 'FAIL', txt.substring(0, 120).replace(/\n/g, ' '));

  // 3) history list
  r = await callTool('history', { action: 'list', limit: 5 });
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = r.json && r.json.result && !r.json.error && (txt.includes('entries') || txt.includes('count'));
  record('history list', pass ? 'PASS' : 'FAIL', txt.substring(0, 150).replace(/\n/g, ' '));

  // 4) read（无 selector，整页文本——dashboard 应有内容或空文本 success）
  r = await callTool('read', {});
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = r.json && r.json.result && !r.json.error;
  record('read', pass ? 'PASS' : 'FAIL', ('len=' + txt.length + ' ') + txt.substring(0, 100).replace(/\n/g, ' '));

  // 5) grep
  r = await callTool('grep', { pattern: '.' });
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = r.json && r.json.result && !r.json.error && txt.includes('count');
  record('grep', pass ? 'PASS' : 'FAIL', txt.substring(0, 150).replace(/\n/g, ' '));

  // 6) evaluate 1+1
  r = await callTool('evaluate', { expression: '1+1' });
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = r.json && r.json.result && !r.json.error && txt.includes('2');
  record('evaluate 1+1', pass ? 'PASS' : 'FAIL', txt.substring(0, 150).replace(/\n/g, ' '));

  // 7) evaluate document.title
  r = await callTool('evaluate', { expression: 'document.title' });
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = r.json && r.json.result && !r.json.error;
  record('evaluate title', pass ? 'PASS' : 'FAIL', txt.substring(0, 150).replace(/\n/g, ' '));

  // 8) run 宏（act scroll down 1 + evaluate）—— run 只收 act/navigate；单步 act scroll
  r = await callTool('run', { steps: [{ tool: 'act', params: { kind: 'scroll', direction: 'down', amount: 1 } }] });
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = r.json && r.json.result && !r.json.error && txt.includes('steps');
  record('run macro', pass ? 'PASS' : 'FAIL', txt.substring(0, 150).replace(/\n/g, ' '));

  // 9) windows list
  r = await callTool('windows', { action: 'list' });
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = r.json && r.json.result && !r.json.error && txt.includes('main');
  record('windows list', pass ? 'PASS' : 'FAIL', txt.substring(0, 150).replace(/\n/g, ' '));

  // 10) 旧别名兼容: click（映射到 act，缺 ref 应报 act 的参数错误——证明别名分发活着）
  r = await callTool('click', { selector: 'body' });
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = r.json && r.json.result; // 命中 act 管线即算通（成功或 act 参数错误都证明别名分发）
  record('click alias->act', pass ? 'PASS' : 'FAIL', txt.substring(0, 150).replace(/\n/g, ' '));

  // 11) upload/pdf unsupported 标注
  r = await callTool('upload', {});
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = txt.includes('unsupported');
  record('upload unsupported', pass ? 'PASS' : 'FAIL', txt.substring(0, 120).replace(/\n/g, ' '));

  r = await callTool('pdf', {});
  txt = r.json && r.json.result && r.json.result.content ? r.json.result.content.map(c => c.text).join('') : r.raw;
  pass = txt.includes('unsupported');
  record('pdf unsupported', pass ? 'PASS' : 'FAIL', txt.substring(0, 120).replace(/\n/g, ' '));

  // 汇总落盘
  fs.writeFileSync('D:/BrowserOS - KaihongOS/evidence/p43/p43a_smoke_results.json', JSON.stringify(results, null, 2));
  const p = results.filter(x => x.verdict === 'PASS').length;
  console.log('----');
  console.log('SMOKE: ' + p + '/' + results.length + ' PASS');
  process.exit(p === results.length ? 0 : 1);
})().catch(e => { console.error('SMOKE ERROR:', e.message); process.exit(1); });
