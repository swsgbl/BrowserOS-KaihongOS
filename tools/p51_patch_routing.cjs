// P51: patch MCPServer + HttpMcpTransport + WsMcpTransport for session routing (LF files, ASCII-only comments)
const fs = require('fs')
const D = '\n'

function patch(file, pairs) {
  let s = fs.readFileSync(file, 'utf8')
  const D = s.includes('\r\n') ? '\r\n' : '\n'
  for (const [oldStr, newStr, tag] of pairs) {
    const o = oldStr.split('\n').join(D)
    const n = newStr.split('\n').join(D)
    if (!s.includes(o)) { console.error('MISS [' + file + ']: ' + tag); process.exit(1) }
    s = s.replace(o, n)
    console.log('ok [' + file.split('/').pop() + ']: ' + tag)
  }
  fs.writeFileSync(file, s, 'utf8')
}

// ---------- HttpMcpTransport ----------
patch('entry/src/main/ets/service/HttpMcpTransport.ets', [
  [
    '  private async handleJsonRpc(conn: ConnectionState, bodyText: string, token: string): Promise<void> {' + D +
    "    const outcome = await McpJsonRpcCore.handleRpc(bodyText, token, 'mcp_http')",
    '  private async handleJsonRpc(conn: ConnectionState, bodyText: string, token: string,' + D +
    '    sessionId: string): Promise<void> {' + D +
    "    const outcome = await McpJsonRpcCore.handleRpc(bodyText, token, 'mcp_http', sessionId)"
  ],
  [
    '    await this.handleJsonRpc(conn, bodyText, token)',
    '    // P51: read Mcp-Session-Id header per request (required for non-initialize calls)' + D +
    "    const sid = this.extractHeader(conn.headers, 'mcp-session-id')" + D +
    '    await this.handleJsonRpc(conn, bodyText, token, sid)'
  ],
  [
    '  private findHeaderEnd(buf: Uint8Array): number {',
    '  /** P51: case-insensitive header lookup */' + D +
    '  private extractHeader(headers: string[], name: string): string {' + D +
    '    if (!headers) {' + D +
    "      return ''" + D +
    '    }' + D +
    "    const lower = name.toLowerCase()" + D +
    '    for (const h of headers) {' + D +
    "      const idx = h.indexOf(':')" + D +
    "      if (idx > 0 && h.substring(0, idx).trim().toLowerCase() === lower) {" + D +
    '        return h.substring(idx + 1).trim()' + D +
    '      }' + D +
    '    }' + D +
    "    return ''" + D +
    '  }' + D + D +
    '  private findHeaderEnd(buf: Uint8Array): number {'
  ]
])

// ---------- WsMcpTransport ----------
patch('entry/src/main/ets/service/WsMcpTransport.ets', [
  [
    "    const outcome = await McpJsonRpcCore.handleRpc(text, conn.token, 'mcp_ws')",
    '    // P51: WS connection-bound session identity' + D +
    "    const outcome = await McpJsonRpcCore.handleRpc(text, conn.token, 'mcp_ws', conn.sessionId)"
  ]
])

// ---------- MCPServer ----------
patch('entry/src/main/ets/service/MCPServer.ets', [
  [
    "import { AuditLogger } from '../storage/AuditLogger'",
    "import { AuditLogger } from '../storage/AuditLogger'" + D +
    "import { McpSessionStore } from './McpSessionStore'"
  ],
  [
    '  async callTool(toolName: string, params: Record<string, Object>, agentId: string,' + D +
    '    token: string): Promise<MCPToolResponse> {',
    '  async callTool(toolName: string, params: Record<string, Object>, agentId: string,' + D +
    '    token: string, sessionId: string): Promise<MCPToolResponse> {'
  ],
  [
    '    // [P43] alias-normalize then fetch handler' + D +
    '    const canonical = this.resolveAlias(toolName)',
    '    // P51 (1b): session routing - resolve target tab from session.ownedTabIds,' + D +
    '    // never fall back to the global active tab (concurrency isolation).' + D +
    '    const session = McpSessionStore.touch(sessionId)' + D +
    '    if (!session) {' + D +
    '      return {' + D +
    "        status: 'error'," + D +
    '        data: null,' + D +
    "        error: 'P51: session required (unknown or expired Mcp-Session-Id)'," + D +
    '        requestId: this.generateRequestId()' + D +
    '      }' + D +
    '    }' + D +
    "    const explicitTab = ((params['tabId'] as string) || (params['page'] as string) || '').trim()" + D +
    '    let routeTab = explicitTab' + D +
    '    if (!routeTab) {' + D +
    "      routeTab = session.ownedTabIds.length > 0 ? session.ownedTabIds[0] : ''" + D +
    '    }' + D +
    '    if (routeTab.length > 0) {' + D +
    '      if (session.ownedTabIds.indexOf(routeTab) >= 0) {' + D +
    '        TabManager.switchTab(routeTab)' + D +
    '        console.info(`[P51] route sid=${sessionId.substring(0, 8)} -> tab ${routeTab} ${toolName}`)' + D +
    '      } else {' + D +
    '        console.warn(`[P51] route reject: tab ${routeTab} not owned by sid=${sessionId.substring(0, 8)}`)' + D +
    '        return {' + D +
    "          status: 'error', data: null," + D +
    "          error: 'P51: tab not owned by this session', requestId: this.generateRequestId()" + D +
    '        }' + D +
    '      }' + D +
    '    }' + D +
    '    if (!routeTab && PAGE_TOOLS.indexOf(toolName) >= 0) {' + D +
    '      return {' + D +
    "        status: 'error', data: null," + D +
    "        error: 'P51: session owns no tab; call tabs{action:new} first'," + D +
    '        requestId: this.generateRequestId()' + D +
    '      }' + D +
    '    }' + D + D +
    '    // [P43] alias-normalize then fetch handler' + D +
    '    const canonical = this.resolveAlias(toolName)'
  ]
])

console.log('all patches applied')
