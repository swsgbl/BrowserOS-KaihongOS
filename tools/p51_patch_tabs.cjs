// P51 part3: MCPServer tabs new/close ownership + PAGE_TOOLS const + redactDeep in AuditLogger
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

// 1. PAGE_TOOLS const after imports (anchor on the McpSessionStore import we added)
rep("import { McpSessionStore } from './McpSessionStore'",
    "import { McpSessionStore } from './McpSessionStore'" + '\n' + '\n' +
    '/** P51: tools that require a routed page (session must own a tab) */' + '\n' +
    "const PAGE_TOOLS: string[] = ['navigate', 'snapshot', 'diff', 'act', 'click', 'type', 'scroll', 'read', 'getText'," + '\n' +
    "  'grep', 'screenshot', 'pdf', 'wait', 'evaluate', 'run', 'download', 'upload']", 'pagetools')

// 2. tabs new: register ownership. handler needs sessionId -> handleTabs signature change
rep('  private handleTabs: ToolHandler = async (params, agentId) => {',
    '  private handleTabs: ToolHandler = async (params, agentId, sessionId) => {', 'tabs-sig')

// but ToolHandler type has 2 params; check its def later. For now patch new/close bodies:
rep("    if (action === 'new') {\n      const url = params['url'] as string || 'about:blank'\n      const tab = TabManager.createTab(false)\n      TabManager.updateTabUrl(tab.tabId, url)\n      const rec12: Record<string, Object> = { 'tabId': tab.tabId, 'url': url }\n    return this.okResponse(rec12)\n    }",
    "    if (action === 'new') {\n      const url = params['url'] as string || 'about:blank'\n      const tab = TabManager.createTab(false)\n      TabManager.updateTabUrl(tab.tabId, url)\n      // P51 (1b)-4: new tab belongs to the calling session\n      if (sessionId) {\n        McpSessionStore.ownTab(sessionId, tab.tabId)\n      }\n      const rec12: Record<string, Object> = { 'tabId': tab.tabId, 'url': url }\n    return this.okResponse(rec12)\n    }", 'tabs-new')

rep("      const ok = TabManager.closeTab(tabId)\n      if (!ok) {\n        return this.errorResponse(ErrorCodes.MCP_003, `tabs close: no such tab ${tabId}`)\n      }\n      const rec13: Record<string, Object> = { 'tabId': tabId, 'closed': true }",
    "      const ok = TabManager.closeTab(tabId)\n      if (!ok) {\n        return this.errorResponse(ErrorCodes.MCP_003, `tabs close: no such tab ${tabId}`)\n      }\n      // P51 (1b)-5: released from owning session (if any)\n      if (sessionId) {\n        McpSessionStore.releaseTab(sessionId, tabId)\n      }\n      const rec13: Record<string, Object> = { 'tabId': tabId, 'closed': true }", 'tabs-close')

// 3. handler invocation passes sessionId
rep('    const response = await handler(adapted, agentId)',
    '    const response = await handler(adapted, agentId, sessionId)', 'handler-call')

fs.writeFileSync(FILE, s, 'utf8')

// 4. ToolHandler type: add optional 3rd param
const TFILE = 'entry/src/main/ets/service/MCPServer.ets'
let t = fs.readFileSync(TFILE, 'utf8')
const typeRe = /type ToolHandler = ([^\r\n]+)/
const m = t.match(typeRe)
if (m) {
  console.log('ToolHandler def: ' + m[1])
} else {
  console.log('ToolHandler def not found (check manually)')
}
