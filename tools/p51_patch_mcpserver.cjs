// P51 part2: MCPServer session routing (idempotent-ish; auto line-ending)
const fs = require('fs')
const FILE = 'entry/src/main/ets/service/MCPServer.ets'
let s = fs.readFileSync(FILE, 'utf8')
const D = s.includes('\r\n') ? '\r\n' : '\n'
const N = (t) => t.split('\n').join(D)

function rep(oldStr, newStr, tag) {
  const o = N(oldStr), n = N(newStr)
  if (s.includes(n)) { console.log('skip (already): ' + tag); return }
  if (!s.includes(o)) { console.error('MISS: ' + tag); process.exit(1) }
  s = s.replace(o, n)
  console.log('ok: ' + tag)
}

rep("import { AuditLogger } from '../storage/AuditLogger'",
    "import { AuditLogger } from '../storage/AuditLogger'" + '\n' +
    "import { McpSessionStore } from './McpSessionStore'", 'import')

rep('  async callTool(toolName: string, params: Record<string, Object>, agentId: string,\n    token: string): Promise<MCPToolResponse> {',
    '  async callTool(toolName: string, params: Record<string, Object>, agentId: string,\n    token: string, sessionId: string): Promise<MCPToolResponse> {', 'sig')

rep("    // [P43] 别名归一后取 handler\n    const canonical = this.resolveAlias(toolName)",
    `    // P51 (1b): session routing - resolve target tab from session.ownedTabIds,
    // never fall back to the global active tab (concurrency isolation).
    const session = McpSessionStore.touch(sessionId)
    if (!session) {
      return {
        status: 'error',
        data: null,
        error: 'P51: session required (unknown or expired Mcp-Session-Id)',
        requestId: this.generateRequestId()
      }
    }
    const explicitTab = ((params['tabId'] as string) || (params['page'] as string) || '').trim()
    let routeTab = explicitTab
    if (!routeTab) {
      routeTab = session.ownedTabIds.length > 0 ? session.ownedTabIds[0] : ''
    }
    if (routeTab.length > 0) {
      if (session.ownedTabIds.indexOf(routeTab) >= 0) {
        TabManager.switchTab(routeTab)
        console.info('[P51] route sid=' + sessionId.substring(0, 8) + ' -> tab ' + routeTab + ' ' + toolName)
      } else {
        console.warn('[P51] route reject: tab ' + routeTab + ' not owned by sid=' + sessionId.substring(0, 8))
        return {
          status: 'error', data: null,
          error: 'P51: tab not owned by this session', requestId: this.generateRequestId()
        }
      }
    }
    if (!routeTab && PAGE_TOOLS.indexOf(toolName) >= 0) {
      return {
        status: 'error', data: null,
        error: 'P51: session owns no tab; call tabs{action:new} first',
        requestId: this.generateRequestId()
      }
    }

    // [P43] 别名归一后取 handler
    const canonical = this.resolveAlias(toolName)`, 'routing')

fs.writeFileSync(FILE, s, 'utf8')
console.log('MCPServer patched')
