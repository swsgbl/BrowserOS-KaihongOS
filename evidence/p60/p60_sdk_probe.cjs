// 官方 MCP SDK (latest) StreamableHTTP 客户端完整握手+调用
const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { StreamableHTTPClientTransport } = require('@modelcontextprotocol/sdk/client/streamableHttp.js');

(async () => {
  const url = 'http://127.0.0.1:19222/mcp?token=' + process.env.MCP_TOKEN;
  console.log('connecting to', url.replace(/token=.*/, 'token=***'));
  const client = new Client({ name: 'p60-sdk-probe', version: '1.0.0' });
  const transport = new StreamableHTTPClientTransport(new URL(url));
  try {
    await client.connect(transport);
    console.log('CONNECT OK');
    const tools = await client.listTools();
    console.log('tools:', tools.tools.length, '->', tools.tools.map(t => t.name).join(','));
    const tab = await client.callTool({ name: 'tabs', arguments: { action: 'list' } });
    console.log('tabs result:', JSON.stringify(tab.content).slice(0, 260));
    const nt = await client.callTool({ name: 'tabs', arguments: { action: 'new' } }); console.log('tabs new:', JSON.stringify(nt.content).slice(0,120)); const nav = await client.callTool({ name: 'navigate', arguments: { url: 'https://example.com' } });
    console.log('navigate result:', JSON.stringify(nav.content).slice(0, 260));
    const rd = await client.callTool({ name: 'read', arguments: {} });
    console.log('read result:', JSON.stringify(rd.content).slice(0, 300));
    await client.close();
    console.log('SDK FULL FLOW PASS');
    process.exit(0);
  } catch (e) {
    console.error('SDK PROBE FAIL:', e.constructor.name, e.message);
    if (e.cause) console.error('cause:', e.cause);
    process.exit(1);
  }
})();
