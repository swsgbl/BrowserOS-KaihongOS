import { socket } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { MCPToolResponse } from '../common/Types'

/**
 * P3: MCP Streamable HTTP 传输层（简化子集）。
 * 基于 @ohos.net.socket TCPSocketServer 的最小 HTTP/1.1 服务：
 * - POST /mcp?token=xxx : JSON-RPC 2.0（initialize / tools/list / tools/call）
 * - GET  /mcp           : 405
 * - OPTIONS /mcp        : 204 + CORS 预检头
 * - 其他                : 404
 * API 版本核对（本机 SDK d.ts）：
 * - TCPSocketServer.listen / on('connect') / off : since 10 (≤14 ✓)
 * - TCPSocketConnection.send/close/on('message')/on('close') : since 10 (≤14 ✓)
 * - TCPSocketServer.close() : since 20 —— stop() 中 try/catch 防御（API14 设备运行时可能无此方法）
 * - util.TextEncoder.encodeInto / util.TextDecoder.create / util.generateRandomUUID : since 7/9 (≤14 ✓)
 */

const TAG = 'MCP-HTTP'
const MAX_HEADER_BYTES: number = 8192
const MAX_BODY_BYTES: number = 1048576

/** MCPServer 注入的回调接口（避免 transport->server 循环依赖） */
export interface McpHttpDelegate {
  validateToken(token: string): boolean
  callTool(toolName: string, params: Record<string, Object>, agentId: string,
    token: string): Promise<MCPToolResponse>
  getToolNames(): string[]
}

// ---------- JSON-RPC / MCP 显式类型（ArkTS 严格模式：禁无类型对象字面量） ----------

class JsonRpcErrorObj {
  code: number = 0
  message: string = ''
}

class JsonRpcResponse {
  jsonrpc: string = '2.0'
  id: Object | null = null
  result: Object | null = null
  error: JsonRpcErrorObj | null = null
}

class McpParamProp {
  type: string = 'string'
  description: string = ''

  constructor(type: string, description: string) {
    this.type = type
    this.description = description
  }
}

class McpInputSchema {
  type: string = 'object'
  properties: Record<string, McpParamProp> = {}
  required: string[] = []
}

class McpToolDescriptor {
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

class McpInitializeResult {
  protocolVersion: string = '2024-11-05'
  capabilities: McpCapabilities = new McpCapabilities()
  serverInfo: McpServerInfo = new McpServerInfo()
}

class McpToolsListResult {
  tools: McpToolDescriptor[] = []
}

class McpContentItem {
  type: string = 'text'
  text: string = ''
}

class McpToolCallResult {
  content: McpContentItem[] = []
  isError: boolean = false
}

/** 单连接状态：累积字节流 + 已 attach 的 client */
class ConnectionState {
  client: socket.TCPSocketConnection
  buffer: Uint8Array = new Uint8Array(0)

  constructor(client: socket.TCPSocketConnection) {
    this.client = client
  }
}

class HttpMcpTransportImpl {
  private server: socket.TCPSocketServer | null = null
  private delegate: McpHttpDelegate | null = null
  private connections: Map<number, ConnectionState> = new Map()
  private sessions: Set<string> = new Set()
  private listening: boolean = false
  private port: number = 0

  async start(port: number, delegate: McpHttpDelegate): Promise<boolean> {
    if (this.listening) {
      console.warn(`[${TAG}] already listening on ${this.port}, ignore start(${port})`)
      return true
    }
    this.delegate = delegate
    const server = socket.constructTCPSocketServerInstance()
    server.on('connect', (client: socket.TCPSocketConnection) => {
      this.onClientConnected(client)
    })
    server.on('error', (err: BusinessError) => {
      console.error(`[${TAG}] server error: ${err.code}/${err.message}`)
    })
    try {
      // 监听 0.0.0.0：VM 内 qemu 端口转发需要 guest 侧全网卡可见
      await server.listen({ address: '0.0.0.0', port: port })
      this.server = server
      this.port = port
      this.listening = true
      console.info(`[${TAG}] listening on 0.0.0.0:${port}`)
      return true
    } catch (e) {
      const detail = (e as BusinessError).code !== undefined ? `${(e as BusinessError).code}/${(e as BusinessError).message}` : JSON.stringify(e)
      console.error(`[${TAG}] listen ${port} failed: ${detail}`)
      return false
    }
  }

  async stop(): Promise<void> {
    this.listening = false
    // 关闭全部活动连接（TCPSocketConnection.close since 10 ✓）
    for (const conn of Array.from(this.connections.values())) {
      try {
        await conn.client.close()
      } catch (e) {
        console.warn(`[${TAG}] close connection failed: ${JSON.stringify(e)}`)
      }
    }
    this.connections.clear()
    this.sessions.clear()
    // TCPSocketServer.close 标注 since 20：API14 设备上可能无此方法，运行时防御
    if (this.server) {
      try {
        await this.server.close()
        console.info(`[${TAG}] server closed (port ${this.port})`)
      } catch (e) {
        console.warn(`[${TAG}] server.close unavailable/failed (expected on API<=19): ${JSON.stringify(e)}`)
      }
      this.server = null
    }
    this.port = 0
  }

  isListening(): boolean {
    return this.listening
  }

  getPort(): number {
    return this.port
  }

  // ---------- 连接生命周期 ----------

  private onClientConnected(client: socket.TCPSocketConnection): void {
    const conn = new ConnectionState(client)
    this.connections.set(client.clientId, conn)
    console.info(`[${TAG}] client connected id=${client.clientId} total=${this.connections.size}`)

    client.on('message', (info: socket.SocketMessageInfo) => {
      try {
        // KaihongOS netstack compat: new signature passes SocketMessageInfo{message}, legacy passes ArrayBuffer directly
        const raw: Object = info as Object
        const ab: ArrayBuffer = (raw !== undefined && raw !== null &&
          (raw as socket.SocketMessageInfo).message !== undefined)
          ? (raw as socket.SocketMessageInfo).message : raw as ArrayBuffer
        console.info(`[${TAG}] onMessage id=${client.clientId} bytes=${ab.byteLength}`)
        this.onBytes(conn, new Uint8Array(ab))
      } catch (e) {
        console.error(`[${TAG}] onMessage error: ${JSON.stringify(e)}`)
      }
    })
    client.on('close', () => {
      this.connections.delete(client.clientId)
      console.info(`[${TAG}] client closed id=${client.clientId} total=${this.connections.size}`)
    })
    client.on('error', (err: BusinessError) => {
      console.error(`[${TAG}] client error id=${client.clientId}: ${err.code}/${err.message}`)
      this.connections.delete(client.clientId)
    })
  }

  // ---------- HTTP/1.1 分帧（Content-Length） ----------

  private onBytes(conn: ConnectionState, chunk: Uint8Array): void {
    let buf = this.concatBytes(conn.buffer, chunk)
    let hex0 = ''
    for (let k = 0; k < Math.min(buf.length, 24); k++) {
      hex0 += buf[k].toString(16).padStart(2, '0') + ' '
    }
    console.info(`[${TAG}] onBytes id=${conn.client.clientId} len=${buf.length} head=${hex0}`)
    // 分帧循环：一条连接上可能连续到达多个请求（keep-alive）
    let guard = 0
    while (guard++ < 32) {
      if (buf.length === 0) {
        break
      }
      let headerEnd = this.findHeaderEnd(buf)
      let loose = false
      if (headerEnd < 0) {
        // P4 fix: GET carries no body; some clients never deliver the standard CRLFCRLF terminator.
        // Loose fallback: request line complete + method GET + no Content-Length + buffer ends with LF
        const firstLineEnd = this.findFirstLineEnd(buf)
        if (firstLineEnd > 0) {
          const reqLineText = this.decodeUtf8(buf.subarray(0, firstLineEnd))
          const method = reqLineText.split(' ')[0] || ''
          const cl = this.parseContentLength(this.decodeUtf8(buf))
          const endsWithLf = buf.length > 0 && buf[buf.length - 1] === 10
          if (method === 'GET' && cl === 0 && endsWithLf) {
            headerEnd = buf.length - 1
            loose = true
            console.warn(`[${TAG}] loose GET framing (no CRLFCRLF, tail=LF), treat ${buf.length}B as header`)
          }
        }
        if (headerEnd < 0) {
          if (buf.length > MAX_HEADER_BYTES) {
          console.error(`[${TAG}] header too large (${buf.length}B), dropping client ${conn.client.clientId}`)
          this.sendSimple(conn, '431 Request Header Fields Too Large', 'header too large').then(() => {
            conn.client.close().catch(() => {
            })
          })
          conn.buffer = new Uint8Array(0)
          return
        }
          let tailHex = ''
          const tailStart = Math.max(0, buf.length - 16)
          for (let k = tailStart; k < buf.length; k++) {
            tailHex += buf[k].toString(16).padStart(2, '0') + ' '
          }
          console.warn(`[${TAG}] header end not found (len=${buf.length} tail=${tailHex.trim()}), waiting`)
          break
        }
      }
      const headerText = this.decodeUtf8(buf.subarray(0, headerEnd))
      const contentLength = loose ? 0 : this.parseContentLength(headerText)
      if (contentLength < 0) {
        console.error(`[${TAG}] invalid Content-Length, dropping client ${conn.client.clientId}`)
        conn.buffer = new Uint8Array(0)
        return
      }
      if (contentLength > MAX_BODY_BYTES) {
        console.error(`[${TAG}] body too large (${contentLength}B)`)
        this.sendSimple(conn, '413 Payload Too Large', 'body too large')
        conn.buffer = new Uint8Array(0)
        return
      }
      const total = loose ? buf.length : headerEnd + 4 + contentLength
      if (buf.length < total) {
        break // body 未收齐，继续累积
      }
      // P4 fix2 (real root cause): decodeWithStream on an EMPTY Uint8Array returns undefined
      // on this netstack; bodyText.length then throws inside async dispatch and the rejection
      // is swallowed -> client hangs forever. GET/empty-body requests must skip decode entirely.
      const bodyText = (loose || contentLength === 0) ? '' : this.decodeUtf8(buf.subarray(headerEnd + 4, total))
      buf = buf.subarray(total)
      conn.buffer = buf
      // 异步处理该请求（不阻塞分帧循环）
      this.dispatch(conn, headerText, bodyText).catch((e: BusinessError) => {
        console.error(`[${TAG}] dispatch async error: ${e.code}/${e.message}`)
      })
    }
    conn.buffer = buf
  }

  // ---------- 路由 ----------

  private async dispatch(conn: ConnectionState, headerText: string, bodyText: string): Promise<void> {
    const lines = headerText.split('\r\n')
    const reqLine = (lines.length > 0 ? lines[0] : '').split(' ')
    const method = reqLine.length > 0 ? reqLine[0] : ''
    const rawPath = reqLine.length > 1 ? reqLine[1] : ''
    const qIdx = rawPath.indexOf('?')
    const path = qIdx >= 0 ? rawPath.substring(0, qIdx) : rawPath
    const query = qIdx >= 0 ? rawPath.substring(qIdx + 1) : ''

    console.info(`[${TAG}] ${method} ${rawPath} client=${conn.client.clientId} bodyLen=${bodyText.length}`)

    try {
      if (method === 'OPTIONS') {
        const optsHeaders: string[] = [
          'Access-Control-Allow-Origin: *',
          'Access-Control-Allow-Methods: POST, GET, OPTIONS',
          'Access-Control-Allow-Headers: Content-Type, Mcp-Session-Id, Authorization',
          'Access-Control-Max-Age: 86400'
        ]
        await this.sendSimple(conn, '204 No Content', '', optsHeaders)
        return
      }
      if (path !== '/mcp') {
        await this.sendSimple(conn, '404 Not Found', '{"error":"not found"}')
        return
      }
      if (method === 'GET') {
        const allowHeaders: string[] = ['Allow: POST, OPTIONS']
        await this.sendSimple(conn, '405 Method Not Allowed', '{"error":"POST only"}', allowHeaders)
        return
      }
      if (method !== 'POST') {
        await this.sendSimple(conn, '405 Method Not Allowed', '{"error":"method not allowed"}')
        return
      }

      // token 鉴权：query ?token=
      const token = this.extractQueryParam(query, 'token')
      if (!this.delegate || !this.delegate.validateToken(token)) {
        console.warn(`[${TAG}] 401 unauthorized (token len=${token.length}) client=${conn.client.clientId}`)
        await this.sendSimple(conn, '401 Unauthorized', '{"error":"invalid token"}')
        return
      }

      await this.handleJsonRpc(conn, bodyText, token)
    } catch (e) {
      const detail = (e as BusinessError).code !== undefined ? `${(e as BusinessError).code}/${(e as BusinessError).message}` : JSON.stringify(e)
      console.error(`[${TAG}] dispatch error: ${detail}`)
      try {
        await this.sendSimple(conn, '500 Internal Server Error', `{"error":${JSON.stringify(detail)}}`)
      } catch (e2) {
        console.error(`[${TAG}] send 500 failed: ${JSON.stringify(e2)}`)
      }
    }
  }

  // ---------- JSON-RPC 2.0 ----------

  private async handleJsonRpc(conn: ConnectionState, bodyText: string, token: string): Promise<void> {
    let root: Record<string, Object> | null = null
    try {
      root = JSON.parse(bodyText) as Record<string, Object>
    } catch (e) {
      await this.sendRpc(conn, null, this.rpcError(-32700, 'Parse error'), [])
      return
    }
    if (!root || root['jsonrpc'] === undefined) {
      await this.sendRpc(conn, null, this.rpcError(-32600, 'Invalid Request'), [])
      return
    }
    const rpcId = root['id'] !== undefined && root['id'] !== null ? root['id'] : null
    const rpcMethod = root['method'] !== undefined && root['method'] !== null ? `${root['method']}` : ''
    const paramsObj = (root['params'] !== undefined && root['params'] !== null)
      ? root['params'] as Record<string, Object> : null

    console.info(`[${TAG}] rpc method=${rpcMethod} id=${JSON.stringify(rpcId)}`)

    if (rpcMethod === 'initialize') {
      const result = new McpInitializeResult()
      result.protocolVersion = '2024-11-05'
      result.capabilities = new McpCapabilities()
      result.serverInfo.name = 'browseros-kaihong'
      result.serverInfo.version = '1.0.0'
      const sessionId = util.generateRandomUUID()
      this.sessions.add(sessionId)
      const extraHeaders: string[] = [`Mcp-Session-Id: ${sessionId}`]
      await this.sendRpc(conn, rpcId, null, extraHeaders, result)
      return
    }

    if (rpcMethod === 'tools/list') {
      const result = new McpToolsListResult()
      result.tools = this.buildToolDescriptors()
      await this.sendRpc(conn, rpcId, null, [], result)
      return
    }

    if (rpcMethod === 'tools/call') {
      const toolName = paramsObj && paramsObj['name'] !== undefined && paramsObj['name'] !== null
        ? `${paramsObj['name']}` : ''
      let args: Record<string, Object> = {}
      if (paramsObj && paramsObj['arguments'] !== undefined && paramsObj['arguments'] !== null) {
        args = paramsObj['arguments'] as Record<string, Object>
      }
      if (!toolName) {
        await this.sendRpc(conn, rpcId, this.rpcError(-32602, 'Invalid params: missing tool name'), [])
        return
      }
      const response = await this.delegate!.callTool(toolName, args, 'mcp_http', token)
      if (response.status === 'success') {
        const result = new McpToolCallResult()
        const item = new McpContentItem()
        item.text = response.data === null ? 'ok' : JSON.stringify(response.data)
        result.content = [item]
        result.isError = false
        await this.sendRpc(conn, rpcId, null, [], result)
      } else {
        await this.sendRpc(conn, rpcId, this.rpcError(-32000, response.error || 'tool call failed'), [])
      }
      return
    }

    await this.sendRpc(conn, rpcId, this.rpcError(-32601, `Method not found: ${rpcMethod}`), [])
  }

  // ---------- 工具表（名字与 MCPServer ToolType 一一对应） ----------

  private buildToolDescriptors(): McpToolDescriptor[] {
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

  // ---------- 响应发送 ----------

  private rpcError(code: number, message: string): JsonRpcErrorObj {
    const err = new JsonRpcErrorObj()
    err.code = code
    err.message = message
    return err
  }

  private async sendRpc(conn: ConnectionState, id: Object | null, error: JsonRpcErrorObj | null,
    extraHeaders: string[], result?: Object): Promise<void> {
    const resp = new JsonRpcResponse()
    resp.id = id
    resp.error = error
    if (error === null && result !== undefined) {
      resp.result = result
    }
    const bodyText = JSON.stringify(resp)
    await this.sendSimple(conn, '200 OK', bodyText, extraHeaders)
  }

  private async sendSimple(conn: ConnectionState, statusLine: string, bodyText: string,
    extraHeaders: string[] = []): Promise<void> {
    const bodyBytes = new util.TextEncoder().encodeInto(bodyText)
    const headers: string[] = [
      `HTTP/1.1 ${statusLine}`,
      'Content-Type: application/json',
      `Content-Length: ${bodyBytes.length}`,
      'Access-Control-Allow-Origin: *',
      'Connection: keep-alive'
    ]
    for (const h of extraHeaders) {
      headers.push(h)
    }
    const headText = headers.join('\r\n') + '\r\n\r\n'
    const headBytes = new util.TextEncoder().encodeInto(headText)
    const out = new Uint8Array(headBytes.length + bodyBytes.length)
    out.set(headBytes, 0)
    out.set(bodyBytes, headBytes.length)
    const data = out.buffer.slice(out.byteOffset, out.byteOffset + out.length)
    try {
      await conn.client.send({ data: data })
    } catch (e) {
      const detail = (e as BusinessError).code !== undefined ? `${(e as BusinessError).code}/${(e as BusinessError).message}` : JSON.stringify(e)
      console.error(`[${TAG}] send failed client=${conn.client.clientId}: ${detail}`)
    }
  }

  // ---------- 解析辅助 ----------

  private findHeaderEnd(buf: Uint8Array): number {
    for (let i = 0; i + 3 < buf.length; i++) {
      if (buf[i] === 13 && buf[i + 1] === 10 && buf[i + 2] === 13 && buf[i + 3] === 10) {
        return i
      }
    }
    return -1
  }

  private findFirstLineEnd(buf: Uint8Array): number {
    for (let i = 0; i + 1 < buf.length; i++) {
      if (buf[i] === 13 && buf[i + 1] === 10) {
        return i
      }
    }
    return -1
  }

  private parseContentLength(headerText: string): number {
    const lines = headerText.split('\r\n')
    for (let i = 1; i < lines.length; i++) {
      const lower = lines[i].toLowerCase()
      if (lower.startsWith('content-length:')) {
        const valueStr = lines[i].substring(15).trim()
        const n = Number(valueStr)
        if (Number.isNaN(n) || n < 0) {
          return -1
        }
        return Math.floor(n)
      }
    }
    return 0
  }

  private extractQueryParam(query: string, key: string): string {
    for (const kv of query.split('&')) {
      if (kv.startsWith(`${key}=`)) {
        return kv.substring(key.length + 1)
      }
    }
    return ''
  }

  private decodeUtf8(bytes: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeWithStream(bytes)
  }

  private concatBytes(a: Uint8Array, b: Uint8Array): Uint8Array {
    const out = new Uint8Array(a.length + b.length)
    out.set(a, 0)
    out.set(b, a.length)
    return out
  }
}

export const HttpMcpTransport = new HttpMcpTransportImpl()
