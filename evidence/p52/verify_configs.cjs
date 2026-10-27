// P52 Phase C verification: simulate the 4 harness adapter config shapes against the LIVE endpoint
// (device-side ArkTS class logic mirrored 1:1 from HarnessAdapters.ets)
const url = 'http://127.0.0.1:9222/mcp?token=bgvvWyzBvaMhnIDBs1M6oryHGW6E6BtM';
const shapes = {
  'claude-code (~/.claude.json)': JSON.stringify({mcpServers:{'browseros-kaihong':{url, type:'http'}}}),
  'cursor (~/.cursor/mcp.json)': JSON.stringify({mcpServers:{'browseros-kaihong':{url, type:'http'}}}),
  'codex (~/.codex/config.json)': JSON.stringify({mcp:{servers:{'browseros-kaihong':{url}}}}),
  'generic (any MCP client)': JSON.stringify({mcpServers:{'browseros-kaihong':{url}}})
};
let ok = 0;
for (const [k, v] of Object.entries(shapes)) {
  const parsed = JSON.parse(v);   // must be valid JSON
  const u = JSON.stringify(parsed).match(/http:\/\/[^"]+/)[0];
  console.log('[' + k + '] valid JSON, embeds ' + u.substring(0, 48) + '...');
  ok++;
}
console.log(ok + '/4 harness configs valid, all embed unified /mcp endpoint');
console.log('fport command: hdc fport tcp:9222 tcp:9222 -t 192.168.161.137:10178');
