// 用官方 MCP SDK 的 StreamableHTTPClientTransport 复现 Claude Code 的连接流程
'.'
const { Client } = require(path + '/dist/client/index.js');
const { StreamableHTTPClientTransport } = require(path + '/dist/client/streamableHttp.js');

(async () => {
  const url = 'http://127.0.0.1:19222/mcp?token=' + process.env.MCP_TOKEN;
  console.log('connecting to', url.replace(/token=.*/, 'token=***'));
  const client = new Client({ name: 'p60-sdk-probe', version: '1.0.0' });
  const transport = new StreamableHTTPClientTransport(new URL(url));
  try {
    await client.connect(transport);
    console.log('CONNECT OK');
    const tools = await client.listTools();
    console.log('tools:', tools.tools.length, tools.tools.slice(0, 5).map(t => t.name).join(','));
    const tab = await client.callTool({ name: 'tabs', arguments: { action: 'list' } });
    console.log('tabs result:', JSON.stringify(tab.content).slice(0, 300));
    await client.close();
    console.log('SDK PROBE PASS');
  } catch (e) {
    console.error('SDK PROBE FAIL:', e.constructor.name, e.message);
    if (e.cause) console.error('cause:', e.cause);
    process.exit(1);
  }
})();
