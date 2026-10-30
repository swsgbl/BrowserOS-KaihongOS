import { util } from '@kit.ArkTS'
import { bundleManager } from '@kit.AbilityKit'
import { redactSensitive } from '../common/Redact'
import { MCPToolResponse } from '../common/Types'
import { McpSessionStore } from './McpSessionStore'
import { AuditEventBus, AuditEventType } from './AuditEventBus'

/**
 * P13: MCP JSON-RPC 分发核心（HTTP 9222 与 WS 8765 共用）。
 * 从 HttpMcpTransport 平移而来（HTTP 路径行为保持等价）：
 * - initialize / tools/list / tools/call 三方法
 * - 响应结构全部显式类（ArkTS 严格模式：禁无类型对象字面量）
 * - 处理结果以 RpcOutcome 返回，由具体传输层（HTTP 响应帧 / WS 文本帧）编码发送
 */

const TAG_RPC: string = 'MCP-RPC'

/** MCPServer 注入的回调接口（避免 transport->server 循环依赖） */
export interface McpHttpDelegate {
  validateToken(token: string): boolean
  callTool(toolName: string, params: Record<string, Object>, agentId: string,
    token: string, sessionId: string): Promise<MCPToolResponse>
  getToolNames(): string[]
}

// ---------- JSON-RPC / MCP 显式类型 ----------

export class JsonRpcErrorObj {
  code: number = 0
  message: string = ''
}

export class JsonRpcResponse {
  jsonrpc: string = '2.0'
  id: Object | null = null
  result: Object | null = null
  error: JsonRpcErrorObj | null = null
}

export class McpParamProp {
  type: string = 'string'
  description: string = ''

  constructor(type: string, description: string) {
    this.type = type
    this.description = description
  }
}

export class McpInputSchema {
  type: string = 'object'
  properties: Record<string, McpParamProp> = {}
  required: string[] = []
}

export class McpToolDescriptor {
  name: string = ''
  description: string = ''
  inputSchema: McpInputSchema = new McpInputSchema()
  aliases: string[] = []   // [P43] 旧工具名（兼容收编，click/type/scroll→act、getText→read、back/forward→history）
}

class McpToolsCapability {
  listChanged: boolean = false
}

class McpCapabilities {
  tools: McpToolsCapability = new McpToolsCapability()
  // P60 interop: strict SDK Zod rejects explicit null here ("expected object, received null").
  // We do not implement resources/prompts — key absence is the valid representation.
}

class McpServerInfo {
  name: string = ''
  title: string = ''   // P52: 2026-07-28 human-readable title
  version: string = ''
}

/**
 * P40-B: MCP initialize instructions（对标上游 claw-server SHARED_BROWSER_GUIDANCE，
 * P58 漂移对齐 c8ac3ca #3078：Tidy up when a task finishes 现为默认开启——
 * 任务完成时主动清理本任务创建的标签，而非保留。）
 */
const MCP_INSTRUCTIONS: string = [
  'You are driving the BrowserOS webview via MCP tools.',
  '- Prefer finishing in the current page: navigate, click, type, scroll, read text, take snapshots.',
  '- Give each step a concrete check: snapshot or getText to verify the effect before moving on.',
  '- Tidy up when a task finishes: close tabs you opened for this task unless the user',
  '  asked to keep them or a page is still useful for inspection.',
  '- The back/forward tools share the page history; use them instead of re-navigating when possible.'
].join('\n')

export class McpInitializeResult {
  protocolVersion: string = '2024-11-05'
  capabilities: McpCapabilities = new McpCapabilities()
  serverInfo: McpServerInfo = new McpServerInfo()
  instructions: string = MCP_INSTRUCTIONS
}

export class McpToolsListResult {
  tools: McpToolDescriptor[] = []
}

export class McpContentItem {
  type: string = 'text'
  text: string = ''
}

export class McpToolCallResult {
  content: McpContentItem[] = []
  isError: boolean = false
}

/** 单次 JSON-RPC 处理结果：传输层据此编码响应 */
export class RpcOutcome {
  statusText: string = '200 OK'      // HTTP 传输层用（WS 不消费）
  extraHeaders: string[] = []        // HTTP 传输层用（Mcp-Session-Id）
  bodyText: string = ''              // JSON-RPC 响应体（两种传输都用）
  sessionId: string = ''             // initialize 时生成；WS 用于 Map<sessionId, conn>
}

class McpJsonRpcCoreImpl {
  /**
   * 处理一条 JSON-RPC 请求文本，产出响应（永不 reject——解析错误也映射为 -32700 响应）。
   * agentId: 审计/敏感确认链用的调用方标识（HTTP 传 mcp_http，WS 传 mcp_ws）
   * incomingSessionId: P51 请求携带的 Mcp-Session-Id；非 initialize 方法必须有效，否则 -32001。
   */
  async handleRpc(bodyText: string, token: string, agentId: string,
    incomingSessionId: string = ''): Promise<RpcOutcome> {
    let root: Record<string, Object> | null = null
    try {
      root = JSON.parse(bodyText) as Record<string, Object>
    } catch (e) {
      return this.outcome(null, this.rpcError(-32700, 'Parse error'))
    }
    if (!root || root['jsonrpc'] === undefined) {
      return this.outcome(null, this.rpcError(-32600, 'Invalid Request'))
    }
    const rpcId = root['id'] !== undefined && root['id'] !== null ? root['id'] : null
    const rpcMethod = root['method'] !== undefined && root['method'] !== null ? `${root['method']}` : ''
    const paramsObj = (root['params'] !== undefined && root['params'] !== null)
      ? root['params'] as Record<string, Object> : null

    console.info(`[${TAG_RPC}] method=${rpcMethod} id=${JSON.stringify(rpcId)} via=${agentId} sid=${incomingSessionId.substring(0, 8)}`)

    // P60: JSON-RPC notification (no id) — MCP Streamable HTTP spec requires 202 + empty body.
    // Returning an error body with id:null breaks strict clients (Claude Code official SDK
    // Zod-parses every response body and fails on id:null / error union) — 实测 ZodError 断连。
    if (rpcId === null) {
      McpSessionStore.touch(incomingSessionId)   // 通知也顺手续期（结果忽略）
      const accepted = new RpcOutcome()
      accepted.statusText = '202 Accepted'
      accepted.bodyText = ''
      console.info(`[${TAG_RPC}] notification ${rpcMethod} accepted (202, empty body)`)
      return accepted
    }

    if (rpcMethod === 'initialize') {
      // P51 (1a): clientInfo.name 入库；会话真值源 = McpSessionStore
      let clientName = agentId
      if (paramsObj && paramsObj['clientInfo'] !== undefined && paramsObj['clientInfo'] !== null) {
        const ci = paramsObj['clientInfo'] as Record<string, Object>
        if (ci['name'] !== undefined && ci['name'] !== null) {
          clientName = `${ci['name']}`
        }
      }
      const session = McpSessionStore.create(clientName)
      const result = new McpInitializeResult()
      // P52: protocol version negotiation — echo 2026-07-28 when requested, else legacy 2024-11-05
      let requestedVersion = ''
      if (paramsObj && paramsObj['protocolVersion'] !== undefined && paramsObj['protocolVersion'] !== null) {
        requestedVersion = `${paramsObj['protocolVersion']}`
      }
      result.protocolVersion = requestedVersion === '2026-07-28' ? '2026-07-28' : '2024-11-05'
      result.capabilities = new McpCapabilities()
      result.serverInfo.name = 'browseros_mcp'
      result.serverInfo.title = 'BrowserOS MCP Server'
      result.serverInfo.version = await McpJsonRpcCoreImpl.appVersion()
      const sessionId = session.sessionId
      const outcome = this.outcome(rpcId, null, result)
      outcome.sessionId = sessionId
      outcome.extraHeaders = [`Mcp-Session-Id: ${sessionId}`]
      return outcome
    }

    // P51 (1a/1b): 会话强制校验 —— 未携带/未知/过期一律 -32001
    const session = McpSessionStore.touch(incomingSessionId)
    if (!session) {
      console.warn(`[${TAG_RPC}] -32001 rejected: method=${rpcMethod} via=${agentId}`)
      return this.outcome(rpcId, this.rpcError(-32001,
        'Session required: unknown or expired Mcp-Session-Id (initialize first)'))
    }

    if (rpcMethod === 'tools/list') {
      const result = new McpToolsListResult()
      result.tools = this.buildToolDescriptors()
      return this.outcome(rpcId, null, result)
    }

    if (rpcMethod === 'tools/call') {
      const toolName = paramsObj && paramsObj['name'] !== undefined && paramsObj['name'] !== null
        ? `${paramsObj['name']}` : ''
      let args: Record<string, Object> = {}
      if (paramsObj && paramsObj['arguments'] !== undefined && paramsObj['arguments'] !== null) {
        args = paramsObj['arguments'] as Record<string, Object>
      }
      if (!toolName) {
        return this.outcome(rpcId, this.rpcError(-32602, 'Invalid params: missing tool name'))
      }
      // P54: 统一审计事件 - 外部 MCP 工具调用起点（sessionId=真实会话；tabId 取 args 显式值）
      const auditT0 = Date.now()
      let auditArgsText = ''
      try {
        auditArgsText = JSON.stringify(args)
      } catch (e) {
        auditArgsText = ''
      }
      const auditTab = args['tabId'] === undefined || args['tabId'] === null ? '' : (args['tabId'] as string)
      AuditEventBus.record(session.sessionId, auditTab, AuditEventType.TOOL_START, toolName, 'running', 0, auditArgsText, '', '')
      const response = await this.callDelegate(toolName, args, agentId, token, session.sessionId)
      // P54: 工具调用终点（status + 耗时 + 错误码）
      AuditEventBus.record(session.sessionId, auditTab, AuditEventType.TOOL_END, toolName,
        response.status === 'success' ? 'ok' : 'error', Date.now() - auditT0, '',
        response.error === null ? '' : (response.error as string),
        response.status === 'success' ? '' : 'MCP_TOOL_FAIL')
      if (response.status === 'success') {
        const result = new McpToolCallResult()
        const item = new McpContentItem()
        // P42 (KAI-075): 工具输出统一脱敏
        // P69-fix: device_agent_tasks 载荷含公开 sha256 摘要（repo manifest），16+hex 掩码会破坏
        // runner 完整性复核（sha256=**** -> MISMATCH）。该工具为 loopback+token 管理面，豁免脱敏。
        if (toolName === 'device_agent_tasks') {
          item.text = response.data === null ? 'ok' : JSON.stringify(response.data)
        } else {
          item.text = redactSensitive(response.data === null ? 'ok' : JSON.stringify(response.data))
        }
        result.content = [item]
        result.isError = false
        return this.outcome(rpcId, null, result)
      }
      return this.outcome(rpcId, this.rpcError(-32000, redactSensitive(response.error || 'tool call failed')))
    }

    return this.outcome(rpcId, this.rpcError(-32601, `Method not found: ${rpcMethod}`))
  }

  private delegate: McpHttpDelegate | null = null

  setDelegate(delegate: McpHttpDelegate): void {
    this.delegate = delegate
  }

  private async callDelegate(toolName: string, args: Record<string, Object>, agentId: string,
    token: string, sessionId: string): Promise<MCPToolResponse> {
    if (!this.delegate) {
      const fallback: MCPToolResponse = {
        status: 'error', data: null, error: 'MCP_999: no delegate bound', requestId: 'req_ws_nodel'
      }
      return fallback
    }
    return this.delegate.callTool(toolName, args, agentId, token, sessionId)
  }

  private outcome(id: Object | null, error: JsonRpcErrorObj | null, result?: Object): RpcOutcome {
    // P60 interop: strict SDK clients (official TS SDK >=1.10, Claude Code 2.x) Zod-reject
    // any SUCCESS response carrying an "error" key (even null). Build the JSON manually
    // so success/error responses each emit only their own key.
    const outcome = new RpcOutcome()
    const idPart: string = id === null ? 'null' : JSON.stringify(id)
    if (error !== null) {
      outcome.bodyText = `{"jsonrpc":"2.0","id":${idPart},"error":${JSON.stringify(error)}}`
    } else if (result !== undefined) {
      outcome.bodyText = `{"jsonrpc":"2.0","id":${idPart},"result":${JSON.stringify(result)}}`
    } else {
      outcome.bodyText = `{"jsonrpc":"2.0","id":${idPart},"result":null}`
    }
    return outcome
  }

  private rpcError(code: number, message: string): JsonRpcErrorObj {
    const err = new JsonRpcErrorObj()
    err.code = code
    err.message = message
    return err
  }

  /** P52: serverInfo.version from bundleManager (fallback '1.0.0') */
  static async appVersion(): Promise<string> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return info.versionName || '1.0.0'
    } catch (e) {
      return '1.0.0'
    }
  }

  // ---------- 工具表（名字与 MCPServer ToolType 一一对应） ----------

  /** [P43] 17 工具描述符（顺序/名称对齐上游 registry.ts；aliases 注明旧名收编，保 smoke/旧客户端兼容） */
  buildToolDescriptors(): McpToolDescriptor[] {
    const tools: McpToolDescriptor[] = []
    tools.push(this.toolDef('tabs', 'Manage browser tabs: list/active/new/close/activate (TabManager passthrough)',
      this.propMap([
        ['action', new McpParamProp('string', 'list | active | new | close | activate (default list)')],
        ['url', new McpParamProp('string', 'URL for action=new (default about:blank)')],
        ['tabId', new McpParamProp('string', 'Tab id for close/activate')],
        ['page', new McpParamProp('string', 'Alias of tabId for close/activate')]
      ]), [], []))
    tools.push(this.toolDef('tab_groups', 'Minimal tab-group semantics: group tabs by agentId; action list/ungroup',
      this.propMap([
        ['action', new McpParamProp('string', 'list | ungroup (default list)')],
        ['group', new McpParamProp('string', 'Group name (agentId) for ungroup')]
      ]), [], []))
    tools.push(this.toolDef('history', 'Browser history: back/forward/list with limit (HistoryManager passthrough)',
      this.propMap([
        ['action', new McpParamProp('string', 'back | forward | list (default list)')],
        ['limit', new McpParamProp('number', 'Max entries for list (default 50)')]
      ]), [], ['back', 'forward']))
    tools.push(this.toolDef('navigate', 'Navigate the webview to a URL',
      this.propMap([
        ['url', new McpParamProp('string', 'The URL to navigate to')],
        ['waitUntil', new McpParamProp('string', 'Optional wait condition (load | domcontentloaded), best-effort')]
      ]), ['url'], []))
    tools.push(this.toolDef('snapshot', 'Get DOM snapshot info of the current page', this.propMap([]), [], []))
    tools.push(this.toolDef('diff', 'Line-level LCS diff between two text snapshots (baseline/current)',
      this.propMap([
        ['baseline', new McpParamProp('string', 'Baseline text (e.g. prior snapshot)')],
        ['current', new McpParamProp('string', 'Current text')]
      ]), ['baseline', 'current'], []))
    tools.push(this.toolDef('act', 'Act on the page. kinds: click, click_at, type, type_at, fill, press, hover, hover_at, focus, check, uncheck, select, scroll, drag, drag_at (aligned with upstream act.ts)',
      this.propMap([
        ['kind', new McpParamProp('string', 'click|click_at|type|type_at|fill|press|hover|hover_at|focus|check|uncheck|select|scroll|drag|drag_at')],
        ['ref', new McpParamProp('string', 'CSS selector of target element')],
        ['text', new McpParamProp('string', 'Text for kind=type/type_at')],
        ['value', new McpParamProp('string', 'Value for kind=fill/select')],
        ['key', new McpParamProp('string', 'Key/combo for kind=press, e.g. Enter, Control+a')],
        ['direction', new McpParamProp('string', 'up | down | left | right for kind=scroll')],
        ['amount', new McpParamProp('number', 'Scroll amount in wheel notches (default 3)')],
        ['x', new McpParamProp('number', 'Viewport x for *_at kinds')],
        ['y', new McpParamProp('number', 'Viewport y for *_at kinds')],
        ['targetRef', new McpParamProp('string', 'Target selector for kind=drag')],
        ['startX', new McpParamProp('number', 'Drag start x for kind=drag_at')],
        ['startY', new McpParamProp('number', 'Drag start y for kind=drag_at')],
        ['endX', new McpParamProp('number', 'Drag end x for kind=drag_at')],
        ['endY', new McpParamProp('number', 'Drag end y for kind=drag_at')],
        ['clear', new McpParamProp('boolean', 'Clear field before type_at/fill')]
      ]), ['kind'], ['click', 'type', 'scroll']))
    tools.push(this.toolDef('download', 'Manage downloads: start(url)/cancel(id)/status(id)/list (DownloadManager passthrough)',
      this.propMap([
        ['action', new McpParamProp('string', 'start | cancel | status | list (default list)')],
        ['url', new McpParamProp('string', 'URL for action=start')],
        ['id', new McpParamProp('string', 'Download id for status/cancel')],
        ['fileName', new McpParamProp('string', 'Optional file name for start')],
        ['mimeType', new McpParamProp('string', 'Optional mime type for start')]
      ]), [], []))
    tools.push(this.toolDef('upload', 'File upload — page <input type=file> triggers system file picker (onShowFileSelector wired P53)',
      this.propMap([
        ['filePath', new McpParamProp('string', 'Reserved: preset file path to inject')]
      ]), [], []))
    tools.push(this.toolDef('read', 'Read page text; optional selector narrows to that element textContent',
      this.propMap([
        ['selector', new McpParamProp('string', 'Optional CSS selector to read a single element')]
      ]), [], ['getText']))
    tools.push(this.toolDef('grep', 'Regex search over page text; returns matches[{line,text}] + count',
      this.propMap([
        ['pattern', new McpParamProp('string', 'JavaScript regular expression source')]
      ]), ['pattern'], []))
    tools.push(this.toolDef('screenshot', 'Capture a screenshot of the current page',
      this.propMap([
        ['quality', new McpParamProp('string', 'low | medium | high')]
      ]), [], []))
    tools.push(this.toolDef('pdf', 'Print page to PDF (A4 portrait, background on) — returns base64 PDF; implemented via WebviewController.createPdf since API 14', this.propMap([]), [], []))
    tools.push(this.toolDef('wait', 'Wait for milliseconds or for a selector to appear',
      this.propMap([
        ['ms', new McpParamProp('number', 'Milliseconds to wait')],
        ['selector', new McpParamProp('string', 'CSS selector to wait for')],
        ['timeout', new McpParamProp('number', 'Selector wait timeout ms')]
      ]), [], []))
    tools.push(this.toolDef('windows', 'Single-window build: list returns [{windowId:main,tabs:N}]; other actions unsupported',
      this.propMap([
        ['action', new McpParamProp('string', 'list | focus | new | close (only list supported)')]
      ]), [], []))
    tools.push(this.toolDef('evaluate_in_page', 'Evaluate a JavaScript expression in the page and return JSON-serialized result (the only script-execution tool; P57 upstream rename of evaluate)',
      this.propMap([
        ['expression', new McpParamProp('string', 'JS expression (evaluated via runJavaScript)')]
      ]), ['expression'], ['evaluate']))
    tools.push(this.toolDef('run', 'Run a macro: sequentially execute an array of act/navigate steps',
      this.propMap([
        ['steps', new McpParamProp('array', 'Array of {tool: act|navigate, params: {...}} steps')]
      ]), ['steps'], []))
    tools.push(this.toolDef('llm_config', '[P65 extension] Manage LLM provider config (baseUrl/apiKey/model) locally: set writes the key through the same Asset Store path as the LLM Hub UI (config.json stays masked); get returns masked key + asset presence; test performs a real LLM roundtrip',
      this.propMap([
        ['action', new McpParamProp('string', 'set | get | test')],
        ['baseUrl', new McpParamProp('string', 'LLM API base URL for set (e.g. https://apihub.agnes-ai.com/v1)')],
        ['apiKey', new McpParamProp('string', 'API key for set (stored encrypted in Asset Store, never echoed in full)')],
        ['model', new McpParamProp('string', 'Model name for set')]
      ]), ['action'], []))
    tools.push(this.toolDef('agent_task', '[P65 extension] Drive the internal AgentEngine programmatically: create{prompt,targetUrl?} starts an agent task and returns agentId; status{agentId} polls progress; result{agentId} returns the final answer',
      this.propMap([
        ['action', new McpParamProp('string', 'create | status | result')],
        ['prompt', new McpParamProp('string', 'Task description for create (the agent uses LLM+BCP tools autonomously)')],
        ['targetUrl', new McpParamProp('string', 'Optional target page URL for create')],
        ['name', new McpParamProp('string', 'Optional agent display name (default mcp_task)')],
        ['agentId', new McpParamProp('string', 'Agent id for status/result')]
      ]), ['action'], []))
    tools.push(this.toolDef('agent_register', '[P67 extension] Device agent registration (inbox mode): register{name,kind} records/refreshes a device-side agent (claude-code/codex/hmharness/custom) in the persistent registry; UI shows it in the AI switcher with an online dot (lastSeen < 2min). Runner calls this on start and every 30s as heartbeat',
      this.propMap([
        ['name', new McpParamProp('string', 'Agent name (unique key, e.g. claude-code)')],
        ['kind', new McpParamProp('string', 'claude-code | codex | hmharness | custom')]
      ]), ['name'], []))
    tools.push(this.toolDef('device_agent_tasks', '[P67 extension] Device agent task inbox: next{agent} claims the oldest pending task file (pending->running); complete{taskId,ok,result} writes back the outcome (result truncated to 32KB)',
      this.propMap([
        ['action', new McpParamProp('string', 'next | complete')],
        ['agent', new McpParamProp('string', 'Agent name for next (claim tasks assigned to it)')],
        ['taskId', new McpParamProp('string', 'Task id for complete')],
        ['ok', new McpParamProp('boolean', 'true=completed, false=failed (default true)')],
        ['result', new McpParamProp('string', 'Final answer text for complete (truncated to 32KB)')]
      ]), ['action'], []))
    return tools
  }

  private toolDef(name: string, description: string, props: Record<string, McpParamProp>,
    required: string[], aliases: string[]): McpToolDescriptor {
    const schema = new McpInputSchema()
    schema.properties = props
    schema.required = required
    const def = new McpToolDescriptor()
    def.name = name
    def.description = description
    def.inputSchema = schema
    def.aliases = aliases
    return def
  }

  private propMap(pairs: [string, McpParamProp][]): Record<string, McpParamProp> {
    const props: Record<string, McpParamProp> = {}
    for (const pair of pairs) {
      props[pair[0]] = pair[1]
    }
    return props
  }
}

export const McpJsonRpcCore = new McpJsonRpcCoreImpl()
