// P60 补丁4: JSON-RPC success 响应不得含 "error":null (官方 SDK strict Zod 拒绝)
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/McpJsonRpcCore.ets';
let s = fs.readFileSync(P, 'utf8');
if (s.includes('P60 interop: strict SDK clients')) { console.error('already patched'); process.exit(0); }

const nl = s.includes("resp.id = id\r\n") ? '\r\n' : '\n';
const oldFn = [
  '  private outcome(id: Object | null, error: JsonRpcErrorObj | null, result?: Object): RpcOutcome {',
  '    const resp = new JsonRpcResponse()',
  '    resp.id = id',
  '    resp.error = error',
  '    if (error === null && result !== undefined) {',
  '      resp.result = result',
  '    }',
  '    const outcome = new RpcOutcome()',
  '    outcome.bodyText = JSON.stringify(resp)',
  '    return outcome',
  '  }',
].join(nl);

if (!s.includes(oldFn)) { console.error('anchor missing'); process.exit(1); }

const newFn = [
  '  private outcome(id: Object | null, error: JsonRpcErrorObj | null, result?: Object): RpcOutcome {',
  '    // P60 interop: strict SDK clients (official TS SDK >=1.10, Claude Code 2.x) Zod-reject',
  '    // any SUCCESS response carrying an "error" key (even null). Build the JSON manually',
  '    // so success/error responses each emit only their own key.',
  '    const outcome = new RpcOutcome()',
  '    const idPart: string = id === null ? \'null\' : JSON.stringify(id)',
  '    if (error !== null) {',
  '      outcome.bodyText = `{"jsonrpc":"2.0","id":${idPart},"error":${JSON.stringify(error)}}`',
  '    } else if (result !== undefined) {',
  '      outcome.bodyText = `{"jsonrpc":"2.0","id":${idPart},"result":${JSON.stringify(result)}}`',
  '    } else {',
  '      outcome.bodyText = `{"jsonrpc":"2.0","id":${idPart},"result":null}`',
  '    }',
  '    return outcome',
  '  }',
].join(nl);

s = s.replace(oldFn, newFn);
fs.writeFileSync(P, s, 'utf8');
console.log('patch4 (error-key-free success responses) applied');
