// 探测 Claude Code 健康检查视角: 各种请求形态的原始响应
const TOKEN = process.env.MCP_TOKEN;
const BASE = 'http://127.0.0.1:19222/mcp?token=' + TOKEN;

async function show(label, opts) {
  try {
    const res = await fetch(BASE, opts);
    const text = await res.text();
    console.log(`\n=== ${label} ===`);
    console.log('status:', res.status);
    console.log('headers:', JSON.stringify(Object.fromEntries(res.headers)));
    console.log('body:', text.slice(0, 600) || '(empty)');
    return res.headers.get('mcp-session-id');
  } catch (e) { console.log(`\n=== ${label} === ERROR ${e.message}`); return null; }
}

(async () => {
  // 1. GET request (Claude Code probe / SSE attempt)
  await show('GET /mcp', { method: 'GET' });
  // 2. initialize
  const sid = await show('POST initialize', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'probe2', version: '1' } } }),
  });
  console.log('\nsession from initialize:', sid);
  const h = { 'Content-Type': 'application/json', 'Mcp-Session-Id': sid };
  // 3. notification
  await show('POST notifications/initialized', {
    method: 'POST', headers: h,
    body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }),
  });
  // 4. tools/list
  await show('POST tools/list', {
    method: 'POST', headers: h,
    body: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} }),
  });
  // 5. DELETE (session terminate probe)
  await show('DELETE /mcp', { method: 'DELETE', headers: h });
})();
