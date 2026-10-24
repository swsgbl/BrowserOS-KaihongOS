import { util } from '@kit.ArkTS'
import { MCPToolResponse } from '../common/Types'

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
    token: string): Promise<MCPToolResponse>
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
}

class McpToolsCapability {
  listChanged: boolean = false
}

class McpCapabilities {
  tools: McpToolsCapability = new McpToolsCapability()
}

class McpServerInfo {
  name: string = ''
  version: string = ''
}

/**
 * P40-B: MCP initialize instructions（对标上游 claw-server SHARED_BROWSER_GUIDANCE，
 * 对齐 browseros-ai/BrowserOS da5f95e「tab group cleanup」净语义：
 * 任务结束时保留有用的页面，除非工具回复要求你关闭本任务的标签组；
 * e1ee0f0 已回滚 1cccd53 的强制 task tab-group cleanup 设置——此处不引入该设置，
 * 引导为"可选/被动"而非默认行为。本项目无 tabs 工具，文案取上游与本工具集的交集。）
 */
const MCP_INSTRUCTIONS: string = [
  'You are driving the BrowserOS webview via MCP tools.',
  '- Prefer finishing in the current page: navigate, click, type, scroll, read text, take snapshots.',
  '- Give each step a concrete check: snapshot or getText to verify the effect before moving on.',
  '- Preserve useful pages that the user may want to inspect; do not navigate away from them',
  '  mid-task unless a step requires it. When the task ends, leave them open instead of',
  "  closing them, unless a tool reply asks you to close your task's tab group.",
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
   */
  async handleRpc(bodyText: string, token: string, agentId: string): Promise<RpcOutcome> {
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

    console.info(`[${TAG_RPC}] method=${rpcMethod} id=${JSON.stringify(rpcId)} via=${agentId}`)

    if (rpcMethod === 'initialize') {
      const result = new McpInitializeResult()
      result.protocolVersion = '2024-11-05'
      result.capabilities = new McpCapabilities()
      result.serverInfo.name = 'browseros-kaihong'
      result.serverInfo.version = '1.0.0'
      const sessionId = util.generateRandomUUID()
      const outcome = this.outcome(rpcId, null, result)
      outcome.sessionId = sessionId
      outcome.extraHeaders = [`Mcp-Session-Id: ${sessionId}`]
      return outcome
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
      const response = await this.callDelegate(toolName, args, agentId, token)
      if (response.status === 'success') {
        const result = new McpToolCallResult()
        const item = new McpContentItem()
        item.text = response.data === null ? 'ok' : JSON.stringify(response.data)
        result.content = [item]
        result.isError = false
        return this.outcome(rpcId, null, result)
      }
      return this.outcome(rpcId, this.rpcError(-32000, response.error || 'tool call failed'))
    }

    return this.outcome(rpcId, this.rpcError(-32601, `Method not found: ${rpcMethod}`))
  }

  private delegate: McpHttpDelegate | null = null

  setDelegate(delegate: McpHttpDelegate): void {
    this.delegate = delegate
  }

  private async callDelegate(toolName: string, args: Record<string, Object>, agentId: string,
    token: string): Promise<MCPToolResponse> {
    if (!this.delegate) {
      const fallback: MCPToolResponse = {
        status: 'error', data: null, error: 'MCP_999: no delegate bound', requestId: 'req_ws_nodel'
      }
      return fallback
    }
    return this.delegate.callTool(toolName, args, agentId, token)
  }

  private outcome(id: Object | null, error: JsonRpcErrorObj | null, result?: Object): RpcOutcome {
    const resp = new JsonRpcResponse()
    resp.id = id
    resp.error = error
    if (error === null && result !== undefined) {
      resp.result = result
    }
    const outcome = new RpcOutcome()
    outcome.bodyText = JSON.stringify(resp)
    return outcome
  }

  private rpcError(code: number, message: string): JsonRpcErrorObj {
    const err = new JsonRpcErrorObj()
    err.code = code
    err.message = message
    return err
  }

  // ---------- 工具表（名字与 MCPServer ToolType 一一对应） ----------

  buildToolDescriptors(): McpToolDescriptor[] {
    const tools: McpToolDescriptor[] = []
    tools.push(this.toolDef('navigate', 'Navigate the webview to a URL',
      this.propMap([['url', new McpParamProp('string', 'The URL to navigate to')]]), ['url']))
    tools.push(this.toolDef('click', 'Click an element by CSS selector',
      this.propMap([['selector', new McpParamProp('string', 'CSS selector of the element')]]), ['selector']))
    tools.push(this.toolDef('type', 'Type text into an input element',
      this.propMap([
        ['selector', new McpParamProp('string', 'CSS selector of the input element')],
        ['text', new McpParamProp('string', 'Text to type')]
      ]), ['selector', 'text']))
    tools.push(this.toolDef('screenshot', 'Capture a screenshot of the current page',
      this.propMap([['quality', new McpParamProp('string', 'low | medium | high')]]), []))
    tools.push(this.toolDef('snapshot', 'Get DOM snapshot info of the current page', this.propMap([]), []))
    tools.push(this.toolDef('scroll', 'Scroll the page',
      this.propMap([
        ['deltaX', new McpParamProp('number', 'Horizontal scroll pixels')],
        ['deltaY', new McpParamProp('number', 'Vertical scroll pixels')]
      ]), ['deltaY']))
    tools.push(this.toolDef('getText', 'Get visible text of the current page', this.propMap([]), []))
    tools.push(this.toolDef('wait', 'Wait for milliseconds or for a selector to appear',
      this.propMap([
        ['ms', new McpParamProp('number', 'Milliseconds to wait')],
        ['selector', new McpParamProp('string', 'CSS selector to wait for')],
        ['timeout', new McpParamProp('number', 'Selector wait timeout ms')]
      ]), []))
    tools.push(this.toolDef('back', 'Go back in history', this.propMap([]), []))
    tools.push(this.toolDef('forward', 'Go forward in history', this.propMap([]), []))
    return tools
  }

  private toolDef(name: string, description: string, props: Record<string, McpParamProp>,
    required: string[]): McpToolDescriptor {
    const schema = new McpInputSchema()
    schema.properties = props
    schema.required = required
    const def = new McpToolDescriptor()
    def.name = name
    def.description = description
    def.inputSchema = schema
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
