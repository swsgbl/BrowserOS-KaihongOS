const http = require('http');
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
    req.setTimeout(15000, () => { req.destroy(); reject(new Error('timeout')); });
    req.write(body);
    req.end();
  });
}

(async () => {
  const init = await rpc('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'p43a-smoke', version: '1.0.0' }
  }, 1);
  console.log('== initialize:', init.status, init.json && init.json.result ? 'result ok' : init.raw.substring(0, 200));

  const tl = await rpc('tools/list', {}, 2);
  if (!tl.json || !tl.json.result || !tl.json.result.tools) {
    console.log('TOOLS/LIST FAILED:', tl.raw.substring(0, 400));
    process.exit(1);
  }
  const names = tl.json.result.tools.map(t => t.name);
  console.log('== tools/list count:', names.length);
  console.log('== names:', names.join(', '));
  const EXPECT = ['tabs','tab_groups','history','navigate','snapshot','diff','act','download','upload','read','grep','screenshot','pdf','wait','windows','evaluate','run'];
  const missing = EXPECT.filter(n => !names.includes(n));
  const extra = names.filter(n => !EXPECT.includes(n));
  console.log('== missing:', missing.length ? missing.join(',') : '(none)');
  console.log('== extra:', extra.length ? extra.join(',') : '(none)');
  const act = tl.json.result.tools.find(t => t.name === 'act');
  console.log('== act aliases:', act && act.aliases ? JSON.stringify(act.aliases) : '(none)');
  const hist = tl.json.result.tools.find(t => t.name === 'history');
  console.log('== history aliases:', hist && hist.aliases ? JSON.stringify(hist.aliases) : '(none)');
  require('fs').writeFileSync('D:/BrowserOS - KaihongOS/evidence/p43/tools_list.json', JSON.stringify(tl.json, null, 2));
  console.log('saved evidence/p43/tools_list.json');

  const pass = missing.length === 0 && names.length === 17;
  console.log(pass ? 'TOOLS_LIST_PASS' : 'TOOLS_LIST_FAIL');
  process.exit(pass ? 0 : 1);
})().catch(e => { console.error('SMOKE ERROR:', e.message); process.exit(1); });
