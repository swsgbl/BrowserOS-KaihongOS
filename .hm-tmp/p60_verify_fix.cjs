// 验证 P60 通知修复: 202 + 空体
const TOKEN = process.env.MCP_TOKEN;
const BASE = 'http://127.0.0.1:19222/mcp?token=' + TOKEN;
(async () => {
  const init = await fetch(BASE, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'p60-verify', version: '1' } } }),
  });
  const sid = init.headers.get('mcp-session-id');
  console.log('init status:', init.status, 'sid:', sid);
  const notif = await fetch(BASE, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'Mcp-Session-Id': sid },
    body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }),
  });
  const nt = await notif.text();
  console.log('notification status:', notif.status, 'body:', JSON.stringify(nt), 'len:', nt.length);
  const list = await fetch(BASE, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'Mcp-Session-Id': sid },
    body: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} }),
  });
  const lj = await list.json();
  console.log('tools/list status:', list.status, 'tools:', lj.result.tools.length);
  // 会话存活验证(通知后续期而非注销)
  const tab = await fetch(BASE, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'Mcp-Session-Id': sid },
    body: JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'tabs', arguments: { action: 'list' } } }),
  });
  const tj = await tab.json();
  console.log('tabs/list ok:', tj.result !== undefined && !tj.error, 'tabCount:', tj.result ? JSON.parse(tj.result.content[0].text).tabs.length : 'n/a');
})();
