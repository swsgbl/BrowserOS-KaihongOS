// P51: patch McpJsonRpcCore.ets for session-enforced dispatch (CRLF-safe, no template literals)
const fs = require('fs')
const path = 'entry/src/main/ets/service/McpJsonRpcCore.ets'
let s = fs.readFileSync(path, 'utf8')
const before = s.length
const D = '\r\n'

function rep(oldStr, newStr, tag) {
  if (!s.includes(oldStr)) { console.error('MISS: ' + tag); process.exit(1) }
  s = s.replace(oldStr, newStr)
  console.log('ok: ' + tag)
}

// 1. import
rep("import { MCPToolResponse } from '../common/Types'",
    "import { MCPToolResponse } from '../common/Types'" + D +
    "import { McpSessionStore } from './McpSessionStore'", 'import')

// 2. signature
rep('   */' + D + '  async handleRpc(bodyText: string, token: string, agentId: string): Promise<RpcOutcome> {',
    '   * incomingSessionId: P51 请求携带的 Mcp-Session-Id；非 initialize 方法必须有效，否则 -32001。' + D + '   */' + D +
    '  async handleRpc(bodyText: string, token: string, agentId: string,' + D +
    '    incomingSessionId: string = \'\'): Promise<RpcOutcome> {', 'signature')

// 3. log line
rep('console.info(`[${TAG_RPC}] method=${rpcMethod} id=${JSON.stringify(rpcId)} via=${agentId}`)',
    'console.info(`[${TAG_RPC}] method=${rpcMethod} id=${JSON.stringify(rpcId)} via=${agentId} sid=${incomingSessionId.substring(0, 8)}`)',
    'logline')

// 4. initialize
const oldInit = [
  '    if (rpcMethod === \'initialize\') {',
  '      const result = new McpInitializeResult()'
].join(D)
const newInit = [
  '    if (rpcMethod === \'initialize\') {',
  '      // P51 (1a): clientInfo.name 入库；会话真值源 = McpSessionStore',
  '      let clientName = agentId',
  '      if (paramsObj && paramsObj[\'clientInfo\'] !== undefined && paramsObj[\'clientInfo\'] !== null) {',
  '        const ci = paramsObj[\'clientInfo\'] as Record<string, Object>',
  '        if (ci[\'name\'] !== undefined && ci[\'name\'] !== null) {',
  '          clientName = `${ci[\'name\']}`',
  '        }',
  '      }',
  '      const session = McpSessionStore.create(clientName)',
  '      const result = new McpInitializeResult()'
].join(D)
rep(oldInit, newInit, 'initialize-half1')

rep('      const sessionId = util.generateRandomUUID()',
    '      const sessionId = session.sessionId', 'initialize-half2')

// 5. session gate
const oldGate = [
  '    if (rpcMethod === \'tools/list\') {',
  '      const result = new McpToolsListResult()'
].join(D)
const newGate = [
  '    // P51 (1a/1b): 会话强制校验 —— 未携带/未知/过期一律 -32001',
  '    const session = McpSessionStore.touch(incomingSessionId)',
  '    if (!session) {',
  '      console.warn(`[${TAG_RPC}] -32001 rejected: method=${rpcMethod} via=${agentId}`)',
  '      return this.outcome(rpcId, this.rpcError(-32001,',
  '        \'Session required: unknown or expired Mcp-Session-Id (initialize first)\'))',
  '    }',
  '',
  '    if (rpcMethod === \'tools/list\') {',
  '      const result = new McpToolsListResult()'
].join(D)
rep(oldGate, newGate, 'gate')

// 6. call pass sessionId
rep('const response = await this.callDelegate(toolName, args, agentId, token)',
    'const response = await this.callDelegate(toolName, args, agentId, token, session.sessionId)', 'callpass')

// 7. interface
rep('  callTool(toolName: string, params: Record<string, Object>, agentId: string,' + D +
    '    token: string): Promise<MCPToolResponse>',
    '  callTool(toolName: string, params: Record<string, Object>, agentId: string,' + D +
    '    token: string, sessionId: string): Promise<MCPToolResponse>', 'iface')

// 8. delegate impl
const oldDel = [
  '  private async callDelegate(toolName: string, args: Record<string, Object>, agentId: string,',
  '    token: string): Promise<MCPToolResponse> {',
  '    if (!this.delegate) {',
  '      const fallback: MCPToolResponse = {',
  '        status: \'error\', data: null, error: \'MCP_999: no delegate bound\', requestId: \'req_ws_nodel\'',
  '      }',
  '      return fallback',
  '    }',
  '    return this.delegate.callTool(toolName, args, agentId, token)',
  '  }'
].join(D)
const newDel = [
  '  private async callDelegate(toolName: string, args: Record<string, Object>, agentId: string,',
  '    token: string, sessionId: string): Promise<MCPToolResponse> {',
  '    if (!this.delegate) {',
  '      const fallback: MCPToolResponse = {',
  '        status: \'error\', data: null, error: \'MCP_999: no delegate bound\', requestId: \'req_ws_nodel\'',
  '      }',
  '      return fallback',
  '    }',
  '    return this.delegate.callTool(toolName, args, agentId, token, sessionId)',
  '  }'
].join(D)
rep(oldDel, newDel, 'delegate')

fs.writeFileSync(path, s, 'utf8')
console.log('done ' + before + ' -> ' + s.length)
