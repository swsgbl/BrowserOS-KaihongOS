// P60 补丁5 完整版: initialize 响应的手工序列化 (capabilities 只含 tools)
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/McpJsonRpcCore.ets';
let s = fs.readFileSync(P, 'utf8');
if (s.includes('P60 interop: strict SDK Zod rejects explicit null')) { console.error('part1 done already'); }
else {
  const nl = s.includes('listChanged: boolean = false\r\n') ? '\r\n' : '\n';
  const oldCap = [
    'class McpCapabilities {',
    '  tools: McpToolsCapability = new McpToolsCapability()',
    '  resources: Object | null = null   // P52: 2026-07-28 spec shape (declared, not implemented)',
    '  prompts: Object | null = null     // P52: 2026-07-28 spec shape (declared, not implemented)',
    '}',
  ].join(nl);
  if (!s.includes(oldCap)) { console.error('capabilities anchor missing'); process.exit(1); }
  const newCap = [
    'class McpCapabilities {',
    '  tools: McpToolsCapability = new McpToolsCapability()',
    '  // P60 interop: strict SDK Zod rejects explicit null here ("expected object, received null").',
    '  // We do not implement resources/prompts — key absence is the valid representation.',
    '}',
  ].join(nl);
  s = s.replace(oldCap, newCap);
  fs.writeFileSync(P, s, 'utf8');
  console.log('patch5: capabilities null fields removed');
}
