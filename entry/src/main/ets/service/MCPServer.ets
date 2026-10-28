import { BCPResult, MCPToolResponse, ToolType } from '../common/Types'
import { BCPEngine } from '../protocol/BCPEngine'
import { SnapshotGenerator } from '../protocol/SnapshotGenerator'
import { ScreenshotCapture } from '../protocol/ScreenshotCapture'
import { AgentEngine } from './AgentEngine'
import { SensitiveOperationDetector } from './SensitiveOperationDetector'
import { AuditLogger } from '../storage/AuditLogger'
import { McpSessionStore } from './McpSessionStore'
import { AuditEventBus, AuditEventType } from './AuditEventBus'
import { redactDeep } from './AuditRedactor'


import { AuditLogEntry } from '../model/AuditLogEntry'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { SensitiveOperationType } from '../common/Types'
import { HttpMcpTransport } from './HttpMcpTransport'
import { McpHttpDelegate } from './McpJsonRpcCore'
import { WsMcpTransport } from './WsMcpTransport'
import { StorageManager } from '../storage/StorageManager'
import { TabManager } from './TabManager'
import { TabGroupManager } from './TabGroupManager'
import { HistoryManager } from './HistoryManager'
import { DownloadManager, DownloadItem } from './DownloadManager'
import { TabInfo } from '../model/TabInfo'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'

/** P51: tools that require a routed page (session must own a tab) */
const PAGE_TOOLS: string[] = ['navigate', 'snapshot', 'diff', 'act', 'click', 'type', 'scroll', 'read', 'getText',
  'grep', 'screenshot', 'pdf', 'wait', 'evaluate_in_page', 'run', 'download', 'upload']


type ToolHandler = (params: Record<string, Object>, agentId: string, sessionId?: string) => Promise<MCPToolResponse>

interface MCPConnectionChangeData {
  status: string
  port: number
}

interface MCPToolCallData {
  requestId: string
  agentId: string
  toolName: string
  params: Record<string, Object>
}

interface MCPToolResponseEventData {
  requestId: string
  response: MCPToolResponse
}

interface MCPResponseData {
  url?: string
  title?: string
  action?: string
  selector?: string
  text?: string
  quality?: string
  deltaX?: number
  deltaY?: number
  ms?: number
  timeout?: number
  result?: string | null
}

/** [P43] tabs list 行（对齐上游 page/url/title 三元组） */
class McpTabLine {
  tabId: string = ''
  url: string = ''
  title: string = ''
  active: boolean = false
}

/** [P43] tab_groups list 行 */
class McpGroupLine {
  group: string = ''
  tabIds: string[] = []
}

/** [P43] history list 行 */
class McpHistoryLine {
  url: string = ''
  title: string = ''
  timestamp: number = 0
}

/** [P43] download list/status 行 */
class McpDownloadLine {
  id: string = ''
  url: string = ''
  fileName: string = ''
  status: string = ''
  receivedBytes: number = 0
  totalBytes: number = 0
  error: string = ''
}

/** [P43] grep 匹配行 */
class McpGrepMatch {
  line: number = 0
  text: string = ''
}

/** [P43] windows list 行（单窗口形态） */
class McpWindowLine {
  windowId: string = ''
  tabs: number = 0
}

/** [P55] windows list 详情（含完整 tab 行） */
class McpWindowDetail {
  windowId: string = ''
  tabs: McpTabLine[] = []
  tabCount: number = 0
}

/** [P62-C] post-transition page info (url/title after settle poll) */
class MCPPageInfo {
  url: string = ''
  title: string = ''
}

/** [P43] diff 输出行 */
class McpDiffLine {
  op: string = ''
  line: number = 0
  text: string = ''
}

class MCPServerImpl implements McpHttpDelegate {
  private port: number = Constants.DEFAULT_MCP_PORT
  private authToken: string = ''
  private running: boolean = false
  private toolHandlers: Map<string, ToolHandler> = new Map()
  private connections: Set<string> = new Set()

  /** [P43] 旧工具名 → 新注册表归一映射（smoke/旧客户端兼容；click/type/scroll→act、getText→read、back/forward→history） */
  private resolveAlias(name: string): string {
    if (name === 'click' || name === 'type' || name === 'scroll') {
      return 'act'
    }
    if (name === 'getText') {
      return 'read'
    }
    if (name === 'back' || name === 'forward') {
      return 'history'
    }
    // P57: evaluate -> evaluate_in_page rename (upstream #3065); old name kept as alias
    if (name === 'evaluate') {
      return 'evaluate_in_page'
    }
    return name
  }

  async start(port: number, authToken: string, wsPort: number = 8765): Promise<boolean> {
    this.port = port
    this.authToken = authToken
    this.registerToolHandlers()

    // P3: 真实网络层接线 —— HttpMcpTransport 监听 127.0.0.1:{port}（P42: loopback only，fport 隧道仍通，设备 IP 直连被拒）
    const listening = await HttpMcpTransport.start(port, this)
    if (!listening) {
      ErrorHandler.handle(new AppError(ErrorCodes.MCP_004, `Port ${port} unavailable`))
      return false
    }

    // P13: WS 传输端点（任务书指定 8765）与 HTTP 同起；失败不阻断 HTTP 已成的启动
    const wsListening = await WsMcpTransport.start(wsPort, this)
    if (!wsListening) {
      console.error('[MCPServer] WS transport start FAILED on port ' + wsPort + ' (HTTP on ' + port + ' stays up)')
    }

    this.running = true
    const startData: MCPConnectionChangeData = { status: 'started', port: this.port }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, startData)
    console.info('[MCPServer] started, HTTP transport listening on 127.0.0.1:' + this.port)

    // P3: token 外显 —— 写入应用沙盒 files/mcp_token.txt（宿主经 hdc cat 可读）
    const tokenFile = StorageManager.getBasePath() + '/mcp_token.txt'
    const saved = await StorageManager.save('mcp_token.txt', this.authToken)
    if (saved) {
      console.info('[MCPServer] authToken persisted to ' + tokenFile)
    } else {
      console.error('[MCPServer] authToken persist FAILED to ' + tokenFile)
    }
    return true
  }

  async stop(): Promise<void> {
    await HttpMcpTransport.stop()
    await WsMcpTransport.stop()
    this.running = false
    this.connections.clear()
    const stopData: MCPConnectionChangeData = { status: 'stopped', port: this.port }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, stopData)
  }

  isRunning(): boolean {
    return this.running
  }

  getPort(): number {
    return this.port
  }

  getAuthToken(): string {
    return this.authToken
  }

  validateToken(token: string): boolean {
    return token === this.authToken
  }

  async callTool(toolName: string, params: Record<string, Object>, agentId: string,
    token: string, sessionId: string): Promise<MCPToolResponse> {
    if (!this.validateToken(token)) {
      return {
        status: 'error',
        data: null,
        error: ErrorCodes.getMessage(ErrorCodes.MCP_001),
        requestId: this.generateRequestId()
      }
    }

    // P51 (1b): session routing - resolve target tab from session.ownedTabIds,
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
        // P51: MCP-created tab 的 Web 组件由 UI 异步渲染（onTabStatusChange -> ForEach -> onAttached
        // -> registerController -> BCPEngine.bindWebView）。路由后若尚未注册，轮询等待（最长 ~3s）。
        const t0 = Date.now()
        while (!TabManager.getWebView(routeTab) && Date.now() - t0 < 3000) {
          await new Promise<void>((res) => setTimeout(res, 100))
        }
        const wv = TabManager.getWebView(routeTab)
        if (wv) {
          BCPEngine.bindWebView(wv.controller, routeTab)
        } else {
          console.warn('[P51] route: webview not ready for tab ' + routeTab + ' after 3s — proceed on current binding')
        }
        console.info('[P51] route sid=' + sessionId.substring(0, 8) + ' -> tab ' + routeTab + ' ' + toolName + ' wvReady=' + (wv !== null))
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
    const canonical = this.resolveAlias(toolName)
    // [P43] 旧名别名适配：click/type/scroll→act 时补 kind 参数（旧客户端只传 selector/text/delta）
    const adapted: Record<string, Object> = {}
    Object.keys(params).forEach(k => { adapted[k] = params[k] })
    if (canonical === 'act' && toolName !== 'act' && adapted['kind'] === undefined) {
      if (toolName === 'click') { adapted['kind'] = 'click' as Object }
      else if (toolName === 'type') { adapted['kind'] = 'type' as Object }
      else if (toolName === 'scroll') { adapted['kind'] = 'scroll' as Object }
    }
    const handler = this.toolHandlers.get(canonical)
    if (!handler) {
      return {
        status: 'error',
        data: null,
        error: ErrorCodes.getMessage(ErrorCodes.MCP_002),
        requestId: this.generateRequestId()
      }
    }

    const requestId = this.generateRequestId()
    const auditEntry = new AuditLogEntry(requestId, agentId, canonical, params['url'] as string || '')
    // P51 (1c): 参数深度脱敏后入审计（type "mypassword123" -> text 前 8 字符 + ***）
    try {
      auditEntry.paramsRedacted = JSON.stringify(redactDeep(params))
    } catch (e) {
      auditEntry.paramsRedacted = ''
    }

    const callData: MCPToolCallData = { requestId: requestId, agentId: agentId, toolName: canonical, params: params }
    EventBus.emit(EventBusEvents.MCP_TOOL_CALL, callData)

    // [P62-G] 30s hard bound on every tool call — a wedged handler (dead JS proxy, mid-nav doc)
    // must fail loudly instead of hanging the request/session indefinitely.
    const TOOL_TIMEOUT_MS = 30000
    let toolTimedOut = false
    const toolRace = Promise.race([
      handler(adapted, agentId, sessionId),
      new Promise<MCPToolResponse>((res) => {
        setTimeout(() => {
          toolTimedOut = true
          res({ status: 'error', data: null, error: 'P62: tool ' + canonical + ' timed out after 30s', requestId: this.generateRequestId() })
        }, TOOL_TIMEOUT_MS)
      })
    ])
    try {
    const response = await toolRace
      auditEntry.setResult(response.status, response.error || '')
      AuditLogger.log(auditEntry)
      const responseData: MCPToolResponseEventData = { requestId: requestId, response: response }
      EventBus.emit(EventBusEvents.MCP_TOOL_RESPONSE, responseData)
      if (toolTimedOut) {
        auditEntry.setResult('error', 'timeout-30s')
      }
      return response
    } catch (e) {
      auditEntry.setResult('error', `${e}`)
      AuditLogger.log(auditEntry)
      return {
        status: 'error',
        data: null,
        error: `${e}`,
        requestId
      }
    }
  }

  getAvailableTools(): string[] {
    return Array.from(this.toolHandlers.keys())
  }

  /** P3: McpHttpDelegate —— 供 HTTP 层拉取工具名列表 */
  getToolNames(): string[] {
    return Array.from(this.toolHandlers.keys())
  }

  private registerToolHandlers(): void {
    // [P43] 17 工具注册表（顺序与名称对齐上游 registry.ts；tools/list 描述符在 McpJsonRpcCore 同步维护）
    this.toolHandlers.set('tabs', this.handleTabs)
    this.toolHandlers.set('tab_groups', this.handleTabGroups)
    this.toolHandlers.set('history', this.handleHistory)
    this.toolHandlers.set('navigate', this.handleNavigate)
    this.toolHandlers.set('snapshot', this.handleSnapshot)
    this.toolHandlers.set('diff', this.handleDiff)
    this.toolHandlers.set('act', this.handleAct)
    this.toolHandlers.set('download', this.handleDownload)
    this.toolHandlers.set('upload', this.handleUpload)
    this.toolHandlers.set('read', this.handleRead)
    this.toolHandlers.set('grep', this.handleGrep)
    this.toolHandlers.set('screenshot', this.handleScreenshot)
    this.toolHandlers.set('pdf', this.handlePdf)
    this.toolHandlers.set('wait', this.handleWait)
    this.toolHandlers.set('windows', this.handleWindows)
    this.toolHandlers.set('evaluate_in_page', this.handleEvaluate)
    this.toolHandlers.set('run', this.handleRun)
  }

  /** [P43] 通用成功响应（data 为任意可 JSON 化对象） */
  private okResponse(data: Record<string, Object>): Promise<MCPToolResponse> {
    const resp: MCPToolResponse = {
      status: 'success',
      data: data,
      error: null,
      requestId: this.generateRequestId()
    }
    return Promise.resolve(resp)
  }

  // ---------- [P43] tabs：TabManager 直通（action: list/active/new/close/activate） ----------

  private handleTabs: ToolHandler = async (params, agentId, sessionId) => {
    const action = params['action'] as string || 'list'
    if (action === 'list') {
      const tabs = TabManager.getAllTabs()
      const activeId = TabManager.getActiveTabId()
      const lines: McpTabLine[] = []
      for (const t of tabs) {
        const line = new McpTabLine()
        line.tabId = t.tabId
        line.url = t.currentUrl
        line.title = t.title
        line.active = t.tabId === activeId
        lines.push(line)
      }
      const rec10: Record<string, Object> = { 'tabs': lines, 'count': lines.length }
    return this.okResponse(rec10)
    }
    if (action === 'active') {
      const id = TabManager.getActiveTabId()
      const t = TabManager.getTab(id)
      if (!t) {
        return this.errorResponse(ErrorCodes.MCP_003, 'tabs active: no active tab')
      }
      const rec11: Record<string, Object> = { 'tabId': id, 'url': t.currentUrl, 'title': t.title, 'active': true }
    return this.okResponse(rec11)
    }
    if (action === 'new') {
      const url = params['url'] as string || 'about:blank'
      const tab = TabManager.createTab(false)
      TabManager.updateTabUrl(tab.tabId, url)
      // P51 (1b)-4: new tab belongs to the calling session
      if (sessionId) {
        McpSessionStore.ownTab(sessionId, tab.tabId)
      }
      const rec12: Record<string, Object> = { 'tabId': tab.tabId, 'url': url }
    return this.okResponse(rec12)
    }
    if (action === 'close') {
      const tabId = (params['tabId'] as string) || (params['page'] as string)
      if (!tabId) {
        return this.errorResponse(ErrorCodes.MCP_003, 'tabs close: tabId (or page) is required')
      }
      const ok = TabManager.closeTab(tabId)
      if (!ok) {
        return this.errorResponse(ErrorCodes.MCP_003, `tabs close: no such tab ${tabId}`)
      }
      // P51 (1b)-5: released from owning session (if any)
      if (sessionId) {
        McpSessionStore.releaseTab(sessionId, tabId)
      }
      // P55: tab removed from any named group on close
      TabGroupManager.cleanupTab(tabId)
      const rec13: Record<string, Object> = { 'tabId': tabId, 'closed': true }
    return this.okResponse(rec13)
    }
    if (action === 'activate') {
      const tabId = (params['tabId'] as string) || (params['page'] as string)
      if (!tabId) {
        return this.errorResponse(ErrorCodes.MCP_003, 'tabs activate: tabId is required')
      }
      const ok = TabManager.switchTab(tabId)
      if (!ok) {
        return this.errorResponse(ErrorCodes.MCP_003, `tabs activate: no such tab ${tabId}`)
      }
      const rec14: Record<string, Object> = { 'tabId': tabId, 'activated': true }
    return this.okResponse(rec14)
    }
    return this.errorResponse(ErrorCodes.MCP_003, `tabs: unsupported action ${action}`)
  }

  // ---------- [P55] tab_groups: named groups (create/join/leave/list/ungroup) via TabGroupManager ----------

  private handleTabGroups: ToolHandler = async (params, agentId) => {
    const action = params['action'] as string || 'list'
    if (action === 'list') {
      const groups = TabGroupManager.list()
      const lines: McpGroupLine[] = []
      for (const g of groups) {
        const line = new McpGroupLine()
        line.group = g.name
        line.tabIds = g.tabIds.slice()
        lines.push(line)
      }
      const recGl: Record<string, Object> = { 'groups': lines, 'count': lines.length }
    return this.okResponse(recGl)
    }
    if (action === 'create') {
      const name = params['name'] as string
      if (!name) {
        return this.errorResponse(ErrorCodes.MCP_003, 'tab_groups create: name is required')
      }
      const g = TabGroupManager.create(name)
      if (!g) {
        return this.errorResponse(ErrorCodes.MCP_003, 'tab_groups create: invalid name')
      }
      const recGc: Record<string, Object> = { 'groupId': g.groupId, 'name': g.name, 'tabIds': g.tabIds.length }
    return this.okResponse(recGc)
    }
    if (action === 'join') {
      const group = (params['group'] as string) || (params['name'] as string)
      const tabIdsRaw = params['tabIds']
      const tabId = params['tabId'] as string
      const ids: string[] = []
      if (tabIdsRaw !== undefined && tabIdsRaw !== null) {
        const arr = tabIdsRaw as Object[]
        if (Array.isArray(arr)) {
          for (const x of arr) { ids.push(`${x}`) }
        }
      }
      if (tabId) {
        ids.push(tabId)
      }
      if (!group || ids.length === 0) {
        return this.errorResponse(ErrorCodes.MCP_003, 'tab_groups join: group and tabIds (or tabId) are required')
      }
      const g = TabGroupManager.findByName(group)
      if (!g) {
        return this.errorResponse(ErrorCodes.MCP_003, `tab_groups join: no such group ${group}`)
      }
      let joined = 0
      const failed: string[] = []
      for (const id of ids) {
        if (TabGroupManager.join(g.groupId, id)) {
          joined++
        } else {
          failed.push(id)
        }
      }
      const recGj: Record<string, Object> = { 'group': group, 'joined': joined, 'failed': failed }
    return this.okResponse(recGj)
    }
    if (action === 'leave') {
      const group = (params['group'] as string) || (params['name'] as string)
      const tabId = params['tabId'] as string
      if (!group || !tabId) {
        return this.errorResponse(ErrorCodes.MCP_003, 'tab_groups leave: group and tabId are required')
      }
      const g = TabGroupManager.findByName(group)
      if (!g) {
        return this.errorResponse(ErrorCodes.MCP_003, `tab_groups leave: no such group ${group}`)
      }
      const ok = TabGroupManager.leave(g.groupId, tabId)
      if (!ok) {
        return this.errorResponse(ErrorCodes.MCP_003, `tab_groups leave: tab ${tabId} not in group ${group}`)
      }
      const recGlv: Record<string, Object> = { 'group': group, 'tabId': tabId, 'left': true }
    return this.okResponse(recGlv)
    }
    if (action === 'ungroup') {
      const group = (params['group'] as string) || (params['name'] as string)
      if (!group) {
        return this.errorResponse(ErrorCodes.MCP_003, 'tab_groups ungroup: group is required')
      }
      const g = TabGroupManager.findByName(group)
      if (!g) {
        return this.errorResponse(ErrorCodes.MCP_003, `tab_groups ungroup: no such group ${group}`)
      }
      const kept = g.tabIds.slice()
      const ok = TabGroupManager.ungroup(g.groupId)
      if (!ok) {
        return this.errorResponse(ErrorCodes.MCP_003, `tab_groups ungroup: failed for ${group}`)
      }
      const recGu: Record<string, Object> = { 'group': group, 'ungrouped': true, 'keptTabs': kept.length }
    return this.okResponse(recGu)
    }
    return this.errorResponse(ErrorCodes.MCP_003, `tab_groups: unsupported action ${action}`)
  }

  // ---------- [P43] history：HistoryManager/BCP 直通（action: back/forward/list；旧 back/forward 工具收编为别名） ----------

  private handleHistory: ToolHandler = async (params, agentId) => {
    const action = params['action'] as string || 'list'
    if (action === 'back') {
      const result = await BCPEngine.back()
      // [P62-C] structured body: settle-poll the transition, then report url/title (was empty {})
      const info = await this.pageInfoAfterTransition()
      const rec1: MCPResponseData = { url: info.url, title: info.title, action: 'back' }
    return this.bcpToMcpResponse(result, rec1)
    }
    if (action === 'forward') {
      const result = await BCPEngine.forward()
      // [P62-C] structured body for forward as well
      const info = await this.pageInfoAfterTransition()
      const rec2: MCPResponseData = { url: info.url, title: info.title, action: 'forward' }
    return this.bcpToMcpResponse(result, rec2)
    }
    if (action === 'list') {
      const limit = (params['limit'] as number) || 50
      const raw = HistoryManager.getAllHistory(limit)
      const lines: McpHistoryLine[] = []
      for (const h of raw) {
        const line = new McpHistoryLine()
        line.url = h.url
        line.title = h.title
        line.timestamp = h.timestamp
        lines.push(line)
      }
      const rec17: Record<string, Object> = { 'entries': lines, 'count': lines.length, 'limit': limit }
    return this.okResponse(rec17)
    }
    return this.errorResponse(ErrorCodes.MCP_003, `history: unsupported action ${action}`)
  }

  // ---------- navigate：现有实现保留；schema 由 JsonRpcCore 补齐上游 waitUntil ----------

  private handleNavigate: ToolHandler = async (params, agentId, sessionId) => {
    const url = params['url'] as string
    if (!url) {
      return this.errorResponse(ErrorCodes.MCP_003, 'Missing url parameter')
    }

    // P44-fix: browseros:// 内建 scheme 拦截 —— 该 scheme 只在 omnibox 路由分发,
    // 直塞 Web 会 ERR_UNKNOWN_URL_SCHEME 且把标签状态污染成白屏。
    if (url.toLowerCase().startsWith('browseros://')) {
      return this.errorResponse(ErrorCodes.MCP_003,
        'browseros:// scheme is not navigable via MCP; use omnibox or menu instead: ' + url)
    }

    const sensitiveType = SensitiveOperationDetector.detectNavigation(agentId, url)
    if (sensitiveType) {
      const confirmed = await SensitiveOperationDetector.requestConfirmation(
        agentId, sensitiveType, url, '')
      if (!confirmed) {
        return this.errorResponse(ErrorCodes.AGT_003, 'Operation rejected by user')
      }
    }

    const result = await BCPEngine.navigate(url)
    // P54: 导航审计事件（tabId 取 session 首个 ownedTab 或空）
    let navTab = ''
    const sess = McpSessionStore.peek(sessionId || '')
    if (sess && sess.ownedTabIds.length > 0) {
      navTab = sess.ownedTabIds[0]
    }
    AuditEventBus.record(sessionId || '', navTab, AuditEventType.NAVIGATION, 'navigate',
      result.success ? 'ok' : 'error', 0, url, result.error === null ? '' : `${result.error}`, '')
    const data: MCPResponseData = { url: url, result: result.data === null ? null : `${result.data}` }
    return this.bcpToMcpResponse(result, data)
  }

  // ---------- [P43] snapshot：现有 markdown 快照保留 ----------

  private handleSnapshot: ToolHandler = async (params, agentId) => {
    const result = await SnapshotGenerator.generate()
    if (!result.success) {
      const dataFail: MCPResponseData = { result: result.data === null ? null : `${result.data}` }
      return this.bcpToMcpResponse(result, dataFail)
    }
    // P55: data is {content, refs} JSON; refs string needs second parse into array
    let content = ''
    let refs: Object[] = []
    try {
      const parsed = JSON.parse(`${result.data}`) as Record<string, Object>
      content = `${parsed['content'] || ''}`
      const refsRaw = `${parsed['refs'] || ''}`
      if (refsRaw.length > 0) {
        const arr = JSON.parse(refsRaw) as Record<string, Object>[]
        if (Array.isArray(arr)) {
          refs = arr
        }
      }
    } catch (e) {
      content = `${result.data}`
    }
    const recSnap: Record<string, Object> = { 'content': content, 'refs': refs, 'refCount': refs.length }
    const snapResp: MCPToolResponse = {
      status: 'success', data: recSnap, error: null, requestId: this.generateRequestId()
    }
    return snapResp
  }

  // ---------- [P43] diff：两段文本行级 diff（LCS；baseline/current 直传，简化自上游快照 id 对） ----------

  private handleDiff: ToolHandler = async (params, agentId) => {
    const baseline = params['baseline'] as string
    const current = params['current'] as string
    if (baseline === undefined || current === undefined) {
      return this.errorResponse(ErrorCodes.MCP_003, 'diff: baseline and current are required')
    }
    const a = baseline.split('\n')
    const b = current.split('\n')
    // 规模保护：超 2000 行降级为端点对比（LCS DP 2000x2000 已是 4M 格）
    if (a.length > 2000 || b.length > 2000) {
      const rec18: Record<string, Object> = {
        'diff': 'page-too-large', 'baselineLines': a.length, 'currentLines': b.length,
        'sameStart': a[0] === b[0], 'sameEnd': a[a.length - 1] === b[b.length - 1]
      }
    return this.okResponse(rec18)
    }
    const n = a.length
    const m = b.length
    const dp: number[][] = []
    for (let i = 0; i <= n; i++) {
      dp.push(new Array<number>(m + 1).fill(0))
    }
    for (let i = n - 1; i >= 0; i--) {
      for (let j = m - 1; j >= 0; j--) {
        dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1])
      }
    }
    const out: McpDiffLine[] = []
    let i = 0
    let j = 0
    while (i < n && j < m) {
      if (a[i] === b[j]) {
        i++
        j++
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        const line = new McpDiffLine()
        line.op = 'removed'
        line.line = i + 1
        line.text = a[i]
        out.push(line)
        i++
      } else {
        const line = new McpDiffLine()
        line.op = 'added'
        line.line = j + 1
        line.text = b[j]
        out.push(line)
        j++
      }
    }
    while (i < n) {
      const line = new McpDiffLine()
      line.op = 'removed'
      line.line = i + 1
      line.text = a[i]
      out.push(line)
      i++
    }
    while (j < m) {
      const line = new McpDiffLine()
      line.op = 'added'
      line.line = j + 1
      line.text = b[j]
      out.push(line)
      j++
    }
    const truncated = out.length > 400
    const changes = truncated ? out.slice(0, 400) : out
    const rec19: Record<string, Object> = { 'changes': changes, 'count': out.length, 'truncated': truncated }
    return this.okResponse(rec19)
  }

  // ---------- [P43] act：15 kinds 分发（对齐上游 act.ts 枚举） ----------
  // click/click_at、type/type_at、scroll 走 BCPEngine 现有管线（含敏感 gate）；
  // 其余 DOM kinds（fill/press/hover/hover_at/focus/check/uncheck/select/drag/drag_at）经 evaluate_in_page 注入同步 helper 内联实现。

  private handleAct: ToolHandler = async (params, agentId) => {
    const kind = params['kind'] as string
    if (!kind) {
      return this.errorResponse(ErrorCodes.MCP_003, 'act: kind is required')
    }
    const ref = (params['ref'] as string) || (params['selector'] as string)
    // P55: Stable SnapshotRef - e<N> refs from snapshot resolve to [data-bcp-ref] CSS selector
    let sel = ''
    if (ref && /^e\d+$/.test(ref)) {
      sel = `[data-bcp-ref="${ref}"]`
    } else {
      sel = ref
    }
    const text = params['text'] as string
    const value = params['value'] as string
    const key = params['key'] as string
    const x = params['x'] as number
    const y = params['y'] as number

    if (kind === 'click' || kind === 'click_at') {
      if (ref) {
        const sensitiveType = SensitiveOperationDetector.detectClick(agentId, ref, text || '')
        if (sensitiveType) {
          const confirmed = await SensitiveOperationDetector.requestConfirmation(agentId, sensitiveType, '', ref)
          if (!confirmed) {
            return this.errorResponse(ErrorCodes.AGT_003, 'Operation rejected by user')
          }
        }
        const result = await BCPEngine.click(sel)
        // [P62-A] a click may submit a form / follow a link — settle before returning so an
        // immediately following snapshot reads the NEW page, not the stale pre-nav document.
        if (result.success) {
          const info = await this.pageInfoAfterTransition()
          const rec3: MCPResponseData = { result: kind, url: info.url, title: info.title }
          return this.bcpToMcpResponse(result, rec3)
        }
        const rec3: MCPResponseData = { result: kind }
    return this.bcpToMcpResponse(result, rec3)
      }
      if (x !== undefined && y !== undefined) {
        // 坐标点击：elementFromIndex 无坐标版——合成 click 事件到 elementFromPoint
        return await this.evalDom(agentId, kind,
          `H.at(${x},${y},'click')`)
      }
      return this.errorResponse(ErrorCodes.MCP_003, 'act click: ref (or x/y) is required')
    }

    if (kind === 'type' || kind === 'type_at') {
      if (text === undefined) {
        return this.errorResponse(ErrorCodes.MCP_003, 'act type: text is required')
      }
      if (ref) {
        const sensitiveType = SensitiveOperationDetector.detectType(agentId, ref, text)
        if (sensitiveType) {
          const confirmed = await SensitiveOperationDetector.requestConfirmation(agentId, sensitiveType, text, ref)
          if (!confirmed) {
            return this.errorResponse(ErrorCodes.AGT_003, 'Operation rejected by user')
          }
        }
        const result = await BCPEngine.type(sel, text)
        const rec4: MCPResponseData = { result: kind }
    return this.bcpToMcpResponse(result, rec4)
      }
      if (x !== undefined && y !== undefined) {
        const clear = params['clear'] === true
        return await this.evalDom(agentId, kind,
          `H.at(${x},${y},'type',${JSON.stringify(text)},${clear})`)
      }
      return this.errorResponse(ErrorCodes.MCP_003, 'act type: ref or x/y is required')
    }

    if (kind === 'fill') {
      if (ref && value !== undefined) {
        const clear = params['clear'] === true
        return await this.evalDom(agentId, kind,
          `H.q(${JSON.stringify(sel)},'fill',${JSON.stringify(value)},${clear})`)
      }
      return this.errorResponse(ErrorCodes.MCP_003, 'act fill: ref and value are required')
    }

    if (kind === 'press') {
      if (!key) {
        return this.errorResponse(ErrorCodes.MCP_003, 'act press: key is required')
      }
      return await this.evalDom(agentId, kind, `H.press(${JSON.stringify(key)})`)
    }

    if (kind === 'hover' || kind === 'hover_at') {
      if (kind === 'hover') {
        if (!ref) {
          return this.errorResponse(ErrorCodes.MCP_003, 'act hover: ref is required')
        }
        return await this.evalDom(agentId, kind, `H.q(${JSON.stringify(sel)},'hover')`)
      }
      if (x === undefined || y === undefined) {
        return this.errorResponse(ErrorCodes.MCP_003, 'act hover_at: x and y are required')
      }
      return await this.evalDom(agentId, kind, `H.at(${x},${y},'hover')`)
    }

    if (kind === 'focus') {
      if (!ref) {
        return this.errorResponse(ErrorCodes.MCP_003, 'act focus: ref is required')
      }
      return await this.evalDom(agentId, kind, `H.q(${JSON.stringify(sel)},'focus')`)
    }

    if (kind === 'check' || kind === 'uncheck') {
      if (!ref) {
        return this.errorResponse(ErrorCodes.MCP_003, `act ${kind}: ref is required`)
      }
      return await this.evalDom(agentId, kind, `H.q(${JSON.stringify(sel)},'check',${kind === 'check'})`)
    }

    if (kind === 'select') {
      if (!ref || value === undefined) {
        return this.errorResponse(ErrorCodes.MCP_003, 'act select: ref and value are required')
      }
      return await this.evalDom(agentId, kind, `H.q(${JSON.stringify(sel)},'select',${JSON.stringify(value)})`)
    }

    if (kind === 'scroll') {
      const direction = (params['direction'] as string) || 'down'
      const amount = (params['amount'] as number) || 3
      // 无 ref：整页滚（换算 notches→像素 100/格）；有 ref：先滚元素入视口再整页滚
      let preScroll = ''
      if (ref) {
        preScroll = `var el=document.querySelector(${JSON.stringify(sel)});if(el){el.scrollIntoView({block:'center'})}else{throw new Error('no match for selector')};`
      }
      const js = `(function(){${preScroll}window.scrollBy({left:${direction === 'left' ? '-' : direction === 'right' ? '' : '0'}${amount * 100},top:${direction === 'up' ? '-' : direction === 'down' ? '' : '0'}${amount * 100},behavior:'instant'});return {ok:true,scrollX:window.scrollX,scrollY:window.scrollY}})()`
      const result = await BCPEngine.evaluate(js)
      const rec5: MCPResponseData = { result: kind }
    return this.bcpToMcpResponse(result, rec5)
    }

    if (kind === 'drag') {
      const targetRef = params['targetRef'] as string
      if (!ref || !targetRef) {
        return this.errorResponse(ErrorCodes.MCP_003, 'act drag: ref and targetRef are required')
      }
      return await this.evalDom(agentId, kind,
        `H.drag(${JSON.stringify(sel)},${JSON.stringify(targetRef)})`)
    }

    if (kind === 'drag_at') {
      const sx = params['startX'] as number
      const sy = params['startY'] as number
      const ex = params['endX'] as number
      const ey = params['endY'] as number
      if (sx === undefined || sy === undefined || ex === undefined || ey === undefined) {
        return this.errorResponse(ErrorCodes.MCP_003, 'act drag_at: startX/startY/endX/endY are required')
      }
      return await this.evalDom(agentId, kind, `H.dragAt(${sx},${sy},${ex},${ey})`)
    }

    return this.errorResponse(ErrorCodes.MCP_003, `act: unknown kind "${kind}"`)
  }

  /** [P43] 同步 DOM helper：随 evaluate_in_page 内联注入（不依赖 bridge 常驻），返回 {ok,...} 结构 */
  private static readonly DOM_HELPERS: string =
    'var H={' +
    'q:function(s,op,arg,arg2){var el=document.querySelector(s);if(!el){throw new Error("no match: "+s)}' +
    'if(op==="fill"){if(arg2){el.value=""}el.value=arg;el.dispatchEvent(new Event("input",{bubbles:true}));el.dispatchEvent(new Event("change",{bubbles:true}));return{ok:true,filled:arg}}' +
    'if(op==="focus"){el.focus();return{ok:true}}' +
    'if(op==="hover"){el.dispatchEvent(new MouseEvent("mouseover",{bubbles:true}));el.dispatchEvent(new MouseEvent("mousemove",{bubbles:true}));return{ok:true}}' +
    'if(op==="check"){if(el.type==="checkbox"||el.type==="radio"){el.checked=arg;el.dispatchEvent(new Event("change",{bubbles:true}));return{ok:true,checked:arg}}throw new Error("not checkable: "+s)}' +
    'if(op==="select"){el.value=arg;el.dispatchEvent(new Event("change",{bubbles:true}));return{ok:true,selected:arg}}' +
    'throw new Error("bad op: "+op)},' +
    'at:function(x,y,op,arg,arg2){var el=document.elementFromPoint(x,y);if(!el){throw new Error("no element at "+x+","+y)}' +
    'if(op==="click"){el.dispatchEvent(new MouseEvent("click",{bubbles:true,clientX:x,clientY:y}));return{ok:true,clicked:true}}' +
    'if(op==="type"){if(el.focus){el.focus()}if(arg2&&el.value!==undefined){el.value=""}el.value=arg||"";el.dispatchEvent(new Event("input",{bubbles:true}));return{ok:true,typed:arg}}' +
    'if(op==="hover"){el.dispatchEvent(new MouseEvent("mouseover",{bubbles:true,clientX:x,clientY:y}));return{ok:true}}' +
    'throw new Error("bad op: "+op)},' +
    'press:function(k){var opts={key:k,bubbles:true,cancelable:true};document.activeElement&&document.activeElement.dispatchEvent(new KeyboardEvent("keydown",opts));document.activeElement&&document.activeElement.dispatchEvent(new KeyboardEvent("keyup",opts));return{ok:true,key:k}},' +
    'drag:function(s,t){var a=document.querySelector(s),b=document.querySelector(t);if(!a||!b){throw new Error("no match for drag refs")}var ra=a.getBoundingClientRect(),rb=b.getBoundingClientRect();return H.dragAt(ra.left+ra.width/2,ra.top+ra.height/2,rb.left+rb.width/2,rb.top+rb.height/2)},' +
    'dragAt:function(x1,y1,x2,y2){var el=document.elementFromPoint(x1,y1);if(!el){throw new Error("no element at drag start")}var o={bubbles:true,cancelable:true,clientX:x1,clientY:y1};el.dispatchEvent(new MouseEvent("mousedown",o));var m={bubbles:true,cancelable:true,clientX:x2,clientY:y2};document.dispatchEvent(new MouseEvent("mousemove",m));var t=document.elementFromPoint(x2,y2)||el;var u={bubbles:true,cancelable:true,clientX:x2,clientY:y2};t.dispatchEvent(new MouseEvent("mouseup",u));t.dispatchEvent(new MouseEvent("drop",u));return{ok:true,from:[x1,y1],to:[x2,y2]}}};'

  /** [P43] act DOM kinds 执行：helper 内联 + 表达式求值；失败如实带回页面侧异常 */
  private async evalDom(agentId: string, kind: string, call: string): Promise<MCPToolResponse> {
    const js = `(function(){${MCPServerImpl.DOM_HELPERS}return ${call}})()`
    const result = await BCPEngine.evaluate(js)
    const rec6: MCPResponseData = { result: kind }
    return this.bcpToMcpResponse(result, rec6)
  }

  // ---------- [P43] download：DownloadManager 直通（action: start/cancel/status/list） ----------

  private handleDownload: ToolHandler = async (params, agentId) => {
    const action = params['action'] as string || 'list'
    if (action === 'list') {
      const items = DownloadManager.getDownloads()
      const lines: McpDownloadLine[] = []
      for (const d of items) {
        lines.push(this.downloadLine(d))
      }
      const rec20: Record<string, Object> = { 'downloads': lines, 'count': lines.length }
    return this.okResponse(rec20)
    }
    if (action === 'status') {
      const id = params['id'] as string
      if (!id) {
        return this.errorResponse(ErrorCodes.MCP_003, 'download status: id is required')
      }
      const hit = this.findDownload(id)
      if (!hit) {
        return this.errorResponse(ErrorCodes.MCP_003, `download status: no such download ${id}`)
      }
      const dl = this.downloadLine(hit)
      const recDl: Record<string, Object> = { 'id': dl.id, 'url': dl.url, 'fileName': dl.fileName, 'status': dl.status, 'receivedBytes': dl.receivedBytes, 'totalBytes': dl.totalBytes, 'error': dl.error }
      return this.okResponse(recDl)
    }
    if (action === 'start') {
      const url = params['url'] as string
      if (!url) {
        return this.errorResponse(ErrorCodes.MCP_003, 'download start: url is required')
      }
      const fileName = params['fileName'] as string || ''
      const mimeType = params['mimeType'] as string || 'application/octet-stream'
      const sensitiveType = SensitiveOperationDetector.detectNavigation(agentId, url)
      if (sensitiveType) {
        const confirmed = await SensitiveOperationDetector.requestConfirmation(agentId, sensitiveType, url, '')
        if (!confirmed) {
          return this.errorResponse(ErrorCodes.AGT_003, 'Operation rejected by user')
        }
      }
      DownloadManager.start(url, fileName, mimeType)
      const rec21: Record<string, Object> = { 'url': url, 'fileName': fileName, 'status': 'started' }
    return this.okResponse(rec21)
    }
    if (action === 'cancel') {
      const id = params['id'] as string
      if (!id) {
        return this.errorResponse(ErrorCodes.MCP_003, 'download cancel: id is required')
      }
      DownloadManager.cancel(id)
      const rec22: Record<string, Object> = { 'id': id, 'canceled': true }
    return this.okResponse(rec22)
    }
    return this.errorResponse(ErrorCodes.MCP_003, `download: unsupported action ${action}`)
  }

  private findDownload(id: string): DownloadItem | null {
    for (const d of DownloadManager.getDownloads()) {
      if (d.id === id) {
        return d
      }
    }
    return null
  }

  private downloadLine(d: DownloadItem): McpDownloadLine {
    const line = new McpDownloadLine()
    line.id = d.id
    line.url = d.url
    line.fileName = d.fileName
    line.status = `${d.status}`
    line.receivedBytes = d.receivedBytes
    line.totalBytes = d.totalBytes
    line.error = d.error
    return line
  }

  // ---------- [P43] upload：ArkWeb 有 onFileSelectorShow（web.d.ts:6532）但 BrowserShell 未接线预设文件注入 ----------
  // 工具面在场、如实返回 unsupported（接线留待后续棒）

  private handleUpload: ToolHandler = async (params, agentId) => {
    // P53: onShowFileSelector 已接线 —— 页面 <input type=file> 的 click 会拉起系统文件选择器，
    // 用户完成选择后文件直接注入页面（UI 闭环）。MCP 程序化指定 filePath 的注入仍受沙盒限制（同上游）。
    const rec23: Record<string, Object> = {
      'supported': true,
      'mode': 'interactive',
      'detail': 'click a file input on the page to trigger the system picker (onShowFileSelector); programmatic filePath injection is sandbox-restricted'
    }
    return this.okResponse(rec23)
  }

  // ---------- [P43] read：页面正文读取（selector 可选→该元素 textContent；否则整页文本）；旧 getText 收编为别名 ----------

  private handleRead: ToolHandler = async (params, agentId) => {
    // P57: no-scripting read (upstream #3065) — snapshot Markdown pipeline first
    // (structured bridge extraction, no per-call JS expression built); legacy JS path only as fallback.
    const selector = params['selector'] as string
    const snapResult = await SnapshotGenerator.generate()
    if (snapResult.success) {
      let content = `${snapResult.data}`
      let refs: Object[] = []
      try {
        const parsed = JSON.parse(content) as Record<string, Object>
        content = `${parsed['content'] || ''}`
        const refsRaw = `${parsed['refs'] || ''}`
        if (refsRaw.length > 0) {
          const arr = JSON.parse(refsRaw) as Record<string, Object>[]
          if (Array.isArray(arr)) { refs = arr }
        }
      } catch (e) {
        // combined JSON unwrap failed — treat whole payload as markdown text
      }
      // selector given: narrow to matching ref lines ([data-bcp-ref=eN] text lines carry ref tags)
      if (selector) {
        const wanted = selector.replace(/\[data-bcp-ref="?/, '').replace(/"?\]$/, '').trim()
        const lines = content.split('\n').filter((ln) => !wanted || ln.includes(wanted))
        content = lines.join('\n')
      }
      // [P62-B] never hand back a literal "null"/empty body as success — explicit error instead
      if (!content || content.trim().length === 0 || content.trim() === 'null' || content.trim() === 'undefined') {
        return this.errorResponse(ErrorCodes.MCP_003,
          'read: page text unavailable (empty snapshot for routed tab — page may be mid-navigation or unrendered)')
      }
      const recRd: Record<string, Object> = { 'source': 'snapshot', 'text': content, 'refCount': refs.length }
      return this.okResponse(recRd)
    }
    console.warn('[P57] read: snapshot pipeline failed, fallback to legacy extraction — ' + `${snapResult.error}`)
    if (selector) {
      const js = `(function(){var el=document.querySelector(${JSON.stringify(selector)});return el?el.textContent:"__NO_MATCH__"})()`
      const result = await BCPEngine.evaluate(js)
      const rec7: Record<string, Object> = { 'selector': selector, 'source': 'fallback' }
    return this.bcpToMcpResponse(result, rec7)
    }
    const result = await BCPEngine.getText()
    const data: MCPResponseData = { result: result.data === null ? null : `${result.data}` }
    return this.bcpToMcpResponse(result, data)
  }

  // ---------- [P43] grep：页面文本正则检索（pattern 必填；返回 matches[{line,text}]+count） ----------

  private handleGrep: ToolHandler = async (params, agentId) => {
    const pattern = params['pattern'] as string
    if (!pattern) {
      return this.errorResponse(ErrorCodes.MCP_003, 'grep: pattern is required')
    }
    let regex: RegExp
    try {
      regex = new RegExp(pattern)
    } catch (e) {
      return this.errorResponse(ErrorCodes.MCP_003, `grep: invalid pattern ${pattern}`)
    }
    // [P62-D] grep must read the SAME source as read (SnapshotGenerator markdown); the old
    // getText path rides the dead-after-nav bridge proxy and returned "null" => 0 hits.
    let body = ''
    const snapResult = await SnapshotGenerator.generate()
    if (snapResult.success) {
      try {
        const parsed = JSON.parse(`${snapResult.data}`) as Record<string, Object>
        body = `${parsed['content'] || ''}`
      } catch (e) {
        body = `${snapResult.data}`
      }
    }
    if (!body) {
      const textResult = await BCPEngine.getText()
      if (!textResult.success) {
        const rec8: MCPResponseData = {}
        return this.bcpToMcpResponse(textResult, rec8)
      }
      body = `${textResult.data}`
      if (body === 'null' || body === 'undefined') {
        body = ''
      }
    }
    const lines = body.split('\n')
    const matches: McpGrepMatch[] = []
    for (let li = 0; li < lines.length; li++) {
      if (regex.test(lines[li])) {
        const m = new McpGrepMatch()
        m.line = li + 1
        m.text = lines[li]
        matches.push(m)
      }
      if (matches.length >= 100) {
        break
      }
    }
    const rec24: Record<string, Object> = { 'matches': matches, 'count': matches.length, 'truncated': matches.length >= 100 }
    return this.okResponse(rec24)
  }

  // ---------- screenshot：现有实现保留 ----------

  private handleScreenshot: ToolHandler = async (params, agentId, sessionId) => {
    const quality = (params['quality'] as string) || 'medium'
    // P54: 按 session 定向 —— 显式 tabId 参数最高，否则 firstOwnedTab（非全局 activeTab）
    let shotTab = ((params['tabId'] as string) || '').trim()
    if (!shotTab && sessionId) {
      const sess = McpSessionStore.touch(sessionId)
      if (sess && sess.ownedTabIds.length > 0) {
        shotTab = sess.ownedTabIds[0]
      }
    }
    if (shotTab) {
      let wv = TabManager.getWebView(shotTab)
      if (!wv) {
        const t0 = Date.now()
        while (!TabManager.getWebView(shotTab) && Date.now() - t0 < 3000) {
          await new Promise<void>((res) => setTimeout(res, 100))
        }
        wv = TabManager.getWebView(shotTab)
      }
      if (wv) {
        BCPEngine.bindWebView(wv.controller, shotTab)
      }
    }
    const result = await ScreenshotCapture.capture(quality, shotTab)
    const data: MCPResponseData = { quality: quality, result: result.data === null ? null : `${result.data}` }
    // P54: 截图审计事件（记录目标 tab，不落图数据）
    AuditEventBus.record(sessionId || '', shotTab, AuditEventType.SCREENSHOT, 'screenshot',
      result.success ? 'ok' : 'error', 0, 'quality=' + quality, result.error === null ? '' : `${result.error}`,
      result.success ? '' : 'SHOT_FAIL')
    return this.bcpToMcpResponse(result, data)
  }

  // ---------- [P43] pdf：ArkWeb 无 printToPDF —— 工具面在场、如实返回 unsupported ----------

  private handlePdf: ToolHandler = async (params, agentId) => {
    // P53: 真实现 —— WebviewController.createPdf (since 14)，A4 纵向 + 打印背景
    const result = await BCPEngine.createPdf()
    if (!result.success) {
      const recFail: Record<string, Object> = { 'supported': true, 'error': result.error || 'createPdf failed' }
      return this.okResponse(recFail)
    }
    const data: MCPResponseData = { result: result.data === null ? null : `${result.data}` }
    return this.bcpToMcpResponse(result, data)
  }

  // ---------- wait：现有实现保留；schema 对齐上游（ms/selector） ----------

  private handleWait: ToolHandler = async (params, agentId) => {
    const ms = params['ms'] as number
    const selector = params['selector'] as string

    if (selector) {
      const timeout = (params['timeout'] as number) || 5000
      const result = await BCPEngine.waitForElement(selector, timeout)
      const data: MCPResponseData = { selector: selector, timeout: timeout, result: result.data === null ? null : `${result.data}` }
      return this.bcpToMcpResponse(result, data)
    } else if (ms) {
      const result = await BCPEngine.wait(ms)
      const data: MCPResponseData = { ms: ms, result: null }
      return this.bcpToMcpResponse(result, data)
    } else {
      return this.errorResponse(ErrorCodes.MCP_003, 'Missing ms or selector parameter')
    }
  }

  // ---------- [P55] windows: single-window build (list with full tabs; focus ok; new/close unsupported) ----------

  private handleWindows: ToolHandler = async (params, agentId) => {
    const action = params['action'] as string || 'list'
    if (action === 'list') {
      const tabs = TabManager.getAllTabs()
      const activeId = TabManager.getActiveTabId()
      const tabLines: McpTabLine[] = []
      for (const t2 of tabs) {
        const line = new McpTabLine()
        line.tabId = t2.tabId
        line.url = t2.currentUrl
        line.title = t2.title
        line.active = t2.tabId === activeId
        tabLines.push(line)
      }
      const winDetail = new McpWindowDetail()
      winDetail.windowId = 'main'
      winDetail.tabs = tabLines
      winDetail.tabCount = tabLines.length
      const winArr: McpWindowDetail[] = [winDetail]
      const recWin: Record<string, Object> = { 'windows': winArr }
    return this.okResponse(recWin)
    }
    if (action === 'focus') {
      const recWf: Record<string, Object> = { 'success': true, 'note': 'single window mode' }
    return this.okResponse(recWf)
    }
    if (action === 'new' || action === 'close') {
      return this.errorResponse(ErrorCodes.MCP_003, `windows ${action}: unsupported on single-window platform`)
    }
    return this.errorResponse(ErrorCodes.MCP_003, `windows: unsupported action ${action}`)
  }

  // ---------- [P55] evaluate: hardened (10s timeout, 64KB truncation, navigation ban) ----------

  private static readonly EVAL_TIMEOUT_MS: number = 10000
  private static readonly EVAL_MAX_RESULT: number = 65536

  private handleEvaluate: ToolHandler = async (params, agentId) => {
    const expression = params['expression'] as string
    if (!expression) {
      return this.errorResponse(ErrorCodes.MCP_003, 'evaluate: expression is required')
    }
    // P55: ban navigation via location assignment (use navigate tool instead)
    if (/(?:window\.)?location\s*(?:\.href\s*=[^=]|\.assign|\.replace\s*\()/.test(expression)) {
      return this.errorResponse(ErrorCodes.MCP_003, 'evaluate: navigation via window.location is banned; use the navigate tool')
    }
    // P55: 10s timeout via Promise.race
    let evalPromise = BCPEngine.evaluate(expression)
    let timeoutHit = false
    const timeoutPromise = new Promise<BCPResult>((resolve) => {
      setTimeout(() => {
        timeoutHit = true
        resolve({ success: false, data: null, error: 'evaluate timeout after 10s' })
      }, MCPServerImpl.EVAL_TIMEOUT_MS)
    })
    const result = await Promise.race([evalPromise, timeoutPromise])
    if (timeoutHit) {
      return this.errorResponse(ErrorCodes.MCP_003, 'evaluate: timed out after 10s')
    }
    if (!result.success) {
      return this.bcpToMcpResponse(result, {})
    }
    // P55: 64KB result cap with truncation marker
    let resultStr = result.data === null ? '' : `${result.data}`
    let truncated = false
    if (resultStr.length > MCPServerImpl.EVAL_MAX_RESULT) {
      resultStr = resultStr.substring(0, MCPServerImpl.EVAL_MAX_RESULT)
      truncated = true
    }
    const recEv: Record<string, Object> = { 'expression': expression, 'result': resultStr, 'truncated': truncated }
    const evResp: MCPToolResponse = {
      status: 'success', data: recEv, error: null, requestId: this.generateRequestId()
    }
    return evResp
  }

  private handleRun: ToolHandler = async (params, agentId) => {
    const stepsRaw = params['steps']
    if (stepsRaw === undefined) {
      return this.errorResponse(ErrorCodes.MCP_003, 'run: steps array is required')
    }
    const steps = stepsRaw as Object[]
    if (!Array.isArray(steps) || steps.length === 0) {
      return this.errorResponse(ErrorCodes.MCP_003, 'run: steps must be a non-empty array')
    }
    const results: MCPToolResponse[] = []
    for (let s = 0; s < steps.length; s++) {
      const stepObj = steps[s] as Record<string, Object>
      const tool = `${stepObj['tool'] || ''}`
      let stepParams: Record<string, Object> = {}
      if (stepObj['params'] !== undefined && stepObj['params'] !== null) {
        stepParams = stepObj['params'] as Record<string, Object>
      }
      if (tool !== 'act' && tool !== 'navigate') {
        results.push(this.errorResponse(ErrorCodes.MCP_003, `run step ${s + 1}: only act/navigate steps supported, got "${tool}"`))
        break
      }
      const handler = this.toolHandlers.get(tool)
      if (!handler) {
        results.push(this.errorResponse(ErrorCodes.MCP_003, `run step ${s + 1}: unknown tool "${tool}"`))
        break
      }
      const resp = await handler(stepParams, agentId)
      results.push(resp)
      if (resp.status !== 'success') {
        break
      }
    }
    const allOk = results.length === steps.length && results.every(r => r.status === 'success')
    const runData: Record<string, Object> = { 'steps': results.length, 'results': results }
    const resp: MCPToolResponse = {
      status: allOk ? 'success' : 'error',
      data: allOk ? runData : null,
      error: allOk ? null : 'run macro aborted',
      requestId: this.generateRequestId()
    }
    return resp
  }

  /** [P62-C/A] wait for the post-action document to settle (readyState complete, url stable),
   *  then read location.href/document.title. Self-contained expression — no bridge dependency. */
  private async pageInfoAfterTransition(maxMs: number = 4000): Promise<MCPPageInfo> {
    const info = new MCPPageInfo()
    // [P62-C] concat-built probe expression so quotes never nest; bridge-free
    const js = '(function(){try{return JSON.stringify({url:location.href,title:document.title,ready:document.readyState})}catch(e){return JSON.stringify({url:"",title:"",ready:"err"})}})()'
    let lastUrl = ''
    let stableSince = 0
    const t0 = Date.now()
    while (Date.now() - t0 < maxMs) {
      const r = await BCPEngine.evaluate(js)
      let url = ''
      let title = ''
      let ready = ''
      try {
        // evaluate returns a JSON string; the probe object is the payload (maybe wrapped {ok,result})
        const outer = JSON.parse(`${r.data}`) as Record<string, Object>
        let probeJson = ''
        if (outer['ok'] !== undefined && outer['result'] !== undefined && outer['result'] !== null) {
          const innerRaw = outer['result']
          probeJson = typeof innerRaw === 'string' ? innerRaw : JSON.stringify(innerRaw)
        } else {
          probeJson = `${r.data}`
        }
        const obj = JSON.parse(probeJson) as Record<string, Object>
        url = `${obj['url'] || ''}`
        title = `${obj['title'] || ''}`
        ready = `${obj['ready'] || ''}`
      } catch (e) { }
      if (url === lastUrl && url.length > 0 && (ready === 'complete' || ready === 'interactive')) {
        if (stableSince === 0) {
          stableSince = Date.now()
        }
        if (Date.now() - stableSince >= 500) {
          info.url = url
          info.title = title
          return info
        }
      } else {
        stableSince = 0
        lastUrl = url
      }
      info.url = url
      info.title = title
      await new Promise<void>((res) => setTimeout(res, 250))
    }
    return info
  }

  private bcpToMcpResponse(bcpResult: BCPResult, data: MCPResponseData): MCPToolResponse {
    const response: MCPToolResponse = {
      status: bcpResult.success ? 'success' : 'error',
      data: bcpResult.success ? data : null,
      error: bcpResult.error,
      requestId: this.generateRequestId()
    }
    return response
  }

  private errorResponse(code: string, message: string): MCPToolResponse {
    return {
      status: 'error',
      data: null,
      error: `${code}: ${message}`,
      requestId: this.generateRequestId()
    }
  }

  private generateRequestId(): string {
    // P42: CSPRNG 随机段（KAI-044）替代 Math.random
    return `req_${Date.now()}_${this.secureRandomChars(8)}`
  }

  generateAuthToken(): string {
    // P42: CSPRNG 生成（KAI-044）——格式不变（AUTH_TOKEN_LENGTH 位字母数字）
    return this.secureRandomChars(Constants.AUTH_TOKEN_LENGTH)
  }

  /** P42: cryptoFramework CSPRNG → base62 字符串；异常回退 util.generateRandomUUID 派生（同为系统安全随机源），绝不用 Math.random */
  private secureRandomChars(len: number): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    try {
      const rand = cryptoFramework.createRandom()
      const bytes: Uint8Array = rand.generateRandomSync(len).data
      let out = ''
      for (let i = 0; i < len; i++) {
        out += chars.charAt(bytes[i] % chars.length)
      }
      return out
    } catch (e) {
      console.error('[MCPServer] generateRandomSync failed, fallback to uuid-derived: ' + JSON.stringify(e))
      let hex = ''
      while (hex.length < len * 2) {
        hex += util.generateRandomUUID(false).replace(/-/g, '')
      }
      let out = ''
      for (let i = 0; i < len; i++) {
        out += chars.charAt(parseInt(hex.substring(i * 2, i * 2 + 2), 16) % chars.length)
      }
      return out
    }
  }
}

export const MCPServer = new MCPServerImpl()
