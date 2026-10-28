// P60 修复: JSON-RPC 通知(无 id)必须 202+空体, 否则 Claude Code 官方 SDK Zod 校验断连
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/McpJsonRpcCore.ets';
let s = fs.readFileSync(P, 'utf8');

const anchor = '    if (rpcMethod === \'initialize\') {';
if (!s.includes(anchor)) { console.error('anchor not found'); process.exit(1); }
if (s.includes('P60: JSON-RPC notification')) { console.error('already patched'); process.exit(0); }

const patch = [
  '    // P60: JSON-RPC notification (no id) — MCP Streamable HTTP spec requires 202 + empty body.',
  '    // Returning an error body with id:null breaks strict clients (Claude Code official SDK',
  '    // Zod-parses every response body and fails on id:null / error union) — 实测 ZodError 断连。',
  '    if (rpcId === null) {',
  '      McpSessionStore.touch(incomingSessionId)   // 通知也顺手续期（结果忽略）',
  '      const accepted = new RpcOutcome()',
  '      accepted.statusText = \'202 Accepted\'',
  '      accepted.bodyText = \'\'',
  '      console.info(`[${TAG_RPC}] notification ${rpcMethod} accepted (202, empty body)`)',
  '      return accepted',
  '    }',
  '',
  '    '
].join('\r\n');

s = s.replace(anchor, patch + anchor);
fs.writeFileSync(P, s, 'utf8');
console.log('patched OK');
