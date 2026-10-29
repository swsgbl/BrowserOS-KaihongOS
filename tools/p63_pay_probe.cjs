#!/bin/node
// P63: sensitiveConfirm=true 下 PAYMENT 关键词导航必须挂起等确认(非直接执行)。
// 探针: navigate https://example.com/pay 挂起至 15s 客户端超时(或服务端 -32000) => PASS
// 对照: navigate https://example.com/?x=formsubmit(含 form/submit 子串, FORM_SUBMIT 已删) 必须直接返回 => PASS
const MCP_URL = process.argv[2];
const http = require('http');
const { URL } = require('url');
function post(bodyObj, timeoutMs, headers = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(MCP_URL);
    const body = JSON.stringify(bodyObj);
    const h = { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body), ...headers };
    const req = http.request({ hostname: u.hostname, port: u.port, path: u.pathname + u.search, method: 'POST', headers: h, timeout: timeoutMs }, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => { resolve({ sid: res.headers['mcp-session-id'], text: d }); });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('client-timeout')); });
    req.write(body); req.end();
  });
}
(async () => {
  const init = await post({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'p63-pay', version: '1.0' } } }, 10000);
  const sid = init.sid;
  await post({ jsonrpc: '2.0', method: 'notifications/initialized' }, 5000, sid ? { 'Mcp-Session-Id': sid } : {});
  // P51: navigate 需要会话自有 tab,先开一个
  const tn = await post({ jsonrpc: '2.0', id: 9, method: 'tools/call', params: { name: 'tabs', arguments: { action: 'new', url: 'https://example.com' } } }, 20000, sid ? { 'Mcp-Session-Id': sid } : {});
  console.log('setup tabs new: ' + tn.text.slice(0, 100));
  // A: PAYMENT 导航应挂起
  let payHung = false; let payDetail = '';
  const t0 = Date.now();
  try {
    const r = await post({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'navigate', arguments: { url: 'https://example.com/pay' } } }, 15000, sid ? { 'Mcp-Session-Id': sid } : {});
    payDetail = 'returned in ' + (Date.now() - t0) + 'ms: ' + r.text.slice(0, 140);
    // 服务端 30s 兜底不会在 15s 内到;若快速返回且非错误=直接执行=FAIL
    payHung = r.text.includes('-32000');
  } catch (e) {
    payHung = e.message === 'client-timeout';
    payDetail = 'client-timeout after ' + (Date.now() - t0) + 'ms (waiting for confirmation)';
  }
  console.log((payHung ? 'PASS' : 'FAIL') + ' [PAY-nav-hangs] ' + payDetail);
  // B: form/submit 子串导航应直接执行(FORM_SUBMIT 档已删)
  const t1 = Date.now();
  let ctlOk = false; let ctlDetail = '';
  try {
    const r = await post({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'navigate', arguments: { url: 'https://example.com/?q=formsubmit' } } }, 25000, sid ? { 'Mcp-Session-Id': sid } : {});
    const fast = Date.now() - t1 < 12000;
    ctlOk = fast && !r.text.includes('-32000');
    ctlDetail = 'returned in ' + (Date.now() - t1) + 'ms body=' + r.text.slice(0, 120);
  } catch (e) {
    ctlDetail = 'timeout/error: ' + e.message;
  }
  console.log((ctlOk ? 'PASS' : 'FAIL') + ' [FORMSUBMIT-nav-direct] ' + ctlDetail);
  process.exit(payHung && ctlOk ? 0 : 1);
})().catch((e) => { console.log('FATAL:', e.message); process.exit(1); });
