import { socket } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { McpJsonRpcCore, McpHttpDelegate } from './McpJsonRpcCore'
import { McpRateLimiter } from './McpRateLimiter'

/**
 * P13: MCP WebSocket 传输端点（端口 8765，任务书指定）。
 *
 * 技术决策：@ohos.net.webSocket 只有客户端（createWebSocket 连出），API14 无 WS 服务端 API，
 * 故自建于 @ohos.net.socket TCPSocketServer（与 HttpMcpTransport 同款模式）：
 * - 握手：GET /mcp?token=xxx + Upgrade: websocket + Sec-WebSocket-Key → 101 +
 *   Sec-WebSocket-Accept = Base64(SHA1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
 *   （公式已在宿主 node 先行验证：dGhlIHNhbXBsZSBub25jZQ== → s3pPLMBiTxaQ9kYGzzhZRbK+xOo=）
 * - 帧解析（客户端→服务器帧必带 mask）：FIN/opcode + MASK/len（126→2B、127→8B）+ 4B key + XOR 解码
 *   opcode：0x1 text=分发 JSON-RPC（复用 McpJsonRpcCore，与 HTTP 9222 完全同核）；
 *   0x8 Close=回 Close 帧后断开清理；0x9 Ping=回 Pong 0xA；0xA Pong=忽略；
 *   0x0 continuation=仅记录不支持（如实注释：MCP JSON-RPC 单帧文本足够，帧上限 1MB）
 * - 帧编码（服务器→客户端不掩码）：FIN|opcode + len 编码 + payload（util.TextEncoder UTF-8）
 * - 生命周期：与 MCPServer.start() 同起同停；多客户端并存，Map<sessionId, conn> 管理，
 *   响应单播回原连接
 * - 敏感确认链不在 WS 层重复实现——callTool 内 SensitiveOperationDetector 经页面层
 *   ConfirmDialog，语义与 HTTP 端点完全一致
 */

const TAG = 'MCP-WS'
const WS_GUID: string = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
const MAX_HANDSHAKE_BYTES: number = 8192
const MAX_FRAME_PAYLOAD: number = 1048576

/** WS 连接状态：握手前=HTTP 头累积，握手后=帧字节流累积 */
class WsConnState {
  client: socket.TCPSocketConnection
  buffer: Uint8Array = new Uint8Array(0)
  handshaken: boolean = false
  token: string = ''
  sessionId: string = ''   // initialize 后登记（会话→连接单播映射）
  closed: boolean = false

  constructor(client: socket.TCPSocketConnection) {
    this.client = client
  }
}

/** 解析出的单帧 */
class WsFrame {
  fin: boolean = false
  opcode: number = 0
  payload: Uint8Array = new Uint8Array(0)
  frameLength: number = 0
}

class WsMcpTransportImpl {
  private server: socket.TCPSocketServer | null = null
  private delegate: McpHttpDelegate | null = null
  private connections: Map<number, WsConnState> = new Map()
  private sessionConns: Map<string, WsConnState> = new Map()
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
      // P42 (KAI-047): loopback only（与 HTTP 9222 同款决策）
      await server.listen({ address: '127.0.0.1', port: port })
      this.server = server
      this.port = port
      this.listening = true
      console.info(`[${TAG}] listening on 127.0.0.1: 8765`)
      return true
    } catch (e) {
      const detail = (e as BusinessError).code !== undefined
        ? `${(e as BusinessError).code}/${(e as BusinessError).message}` : JSON.stringify(e)
      console.error(`[${TAG}] listen ${port} failed: ${detail}`)
      return false
    }
  }

  async stop(): Promise<void> {
    this.listening = false
    for (const conn of Array.from(this.connections.values())) {
      this.closeConn(conn, 1001, 'server shutdown')
    }
    this.connections.clear()
    this.sessionConns.clear()
    // TCPSocketServer.close 标注 since 20：API14 设备上可能无此方法，运行时防御（与 HTTP 层同款）
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
    const conn = new WsConnState(client)
    this.connections.set(client.clientId, conn)
    console.info(`[${TAG}] client connected id=${client.clientId} total=${this.connections.size}`)

    client.on('message', (info: socket.SocketMessageInfo) => {
      try {
        // KaihongOS netstack compat（与 HttpMcpTransport 同款）：
        // 新签名传 SocketMessageInfo{message}，旧签名直接传 ArrayBuffer
        const raw: Object = info as Object
        const ab: ArrayBuffer = (raw !== undefined && raw !== null &&
          (raw as socket.SocketMessageInfo).message !== undefined)
          ? (raw as socket.SocketMessageInfo).message : raw as ArrayBuffer
        this.onBytes(conn, new Uint8Array(ab))
      } catch (e) {
        console.error(`[${TAG}] onMessage error: ${JSON.stringify(e)}`)
      }
    })
    client.on('close', () => {
      this.cleanupConn(conn)
      console.info(`[${TAG}] client closed id=${client.clientId} total=${this.connections.size}`)
    })
    client.on('error', (err: BusinessError) => {
      console.error(`[${TAG}] client error id=${client.clientId}: ${err.code}/${err.message}`)
      this.cleanupConn(conn)
    })
  }

  private cleanupConn(conn: WsConnState): void {
    if (conn.sessionId !== '') {
      this.sessionConns.delete(conn.sessionId)
    }
    this.connections.delete(conn.client.clientId)
    McpRateLimiter.reset(`ws_${conn.client.clientId}`)
  }

  // ---------- 字节流入口：握手前 HTTP 累积 / 握手后 WS 帧累积 ----------

  private onBytes(conn: WsConnState, chunk: Uint8Array): void {
    conn.buffer = this.concatBytes(conn.buffer, chunk)
    if (!conn.handshaken) {
      this.tryHandshake(conn)
    }
    if (!conn.handshaken) {
      return // 未收齐（等待更多字节）或已被拒绝（rejectHttp 自行断开清理）
    }
    this.consumeFrames(conn)
  }

  // ---------- WebSocket 握手 ----------

  private tryHandshake(conn: WsConnState): void {
    const headerEnd = this.findHeaderEnd(conn.buffer)
    if (headerEnd < 0) {
      if (conn.buffer.length > MAX_HANDSHAKE_BYTES) {
        console.error(`[${TAG}] handshake request too large (${conn.buffer.length}B), dropping`)
        this.rejectHttp(conn, '431 Request Header Fields Too Large', 'header too large')
      }
      return
    }
    const headerText = this.decodeUtf8(conn.buffer.subarray(0, headerEnd))
    conn.buffer = conn.buffer.subarray(headerEnd + 4)

    const lines = headerText.split('\r\n')
    const reqLine = (lines.length > 0 ? lines[0] : '').split(' ')
    const method = reqLine.length > 0 ? reqLine[0] : ''
    const rawPath = reqLine.length > 1 ? reqLine[1] : ''
    const qIdx = rawPath.indexOf('?')
    const path = qIdx >= 0 ? rawPath.substring(0, qIdx) : rawPath
    const query = qIdx >= 0 ? rawPath.substring(1 + qIdx) : rawPath

    let upgrade: string = ''
    let wsKey: string = ''
    let connection: string = ''
    for (let i = 1; i < lines.length; i++) {
      const cIdx = lines[i].indexOf(':')
      if (cIdx <= 0) {
        continue
      }
      const name = lines[i].substring(0, cIdx).trim().toLowerCase()
      const value = lines[i].substring(cIdx + 1).trim()
      if (name === 'upgrade') {
        upgrade = value.toLowerCase()
      } else if (name === 'sec-websocket-key') {
        wsKey = value
      } else if (name === 'connection') {
        connection = value.toLowerCase()
      }
    }

    console.info(`[${TAG}] handshake ${method} ${rawPath} client=${conn.client.clientId}`)

    // 规范校验：GET /mcp + Upgrade: websocket + Connection 含 upgrade + Sec-WebSocket-Key
    if (method !== 'GET' || path !== '/mcp' || upgrade !== 'websocket' ||
      connection.indexOf('upgrade') < 0 || wsKey === '') {
      console.warn(`[${TAG}] bad handshake (method=${method} path=${path} upgrade=${upgrade})`)
      this.rejectHttp(conn, '400 Bad Request', '{"error":"expected websocket upgrade"}')
      return
    }

    // token 鉴权：?token= 复用 validateToken（与 HTTP 端点同语义）
    const token = this.extractQueryParam(query, 'token')
    if (!this.delegate || !this.delegate.validateToken(token)) {
      console.warn(`[${TAG}] 401 unauthorized ws handshake (token len=${token.length}) client=${conn.client.clientId}`)
      this.rejectHttp(conn, '401 Unauthorized', '{"error":"invalid token"}')
      return
    }

    const accept = this.computeAccept(wsKey)
    if (accept === '') {
      this.rejectHttp(conn, '400 Bad Request', '{"error":"bad sec-websocket-key"}')
      return
    }
    conn.token = token
    conn.handshaken = true
    const head =
      'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${accept}\r\n` +
      '\r\n'
    this.sendRaw(conn, new util.TextEncoder().encodeInto(head)).then(() => {
      console.info(`[${TAG}] 101 switching protocols client=${conn.client.clientId}`)
    })
    // 握手响应发出后，buffer 里可能已带着首帧字节，继续消费
    this.consumeFrames(conn)
  }

  /** Sec-WebSocket-Accept = Base64(SHA1(key + GUID))；cryptoFramework SHA1 + util Base64Helper */
  private computeAccept(key: string): string {
    try {
      const input = new util.TextEncoder().encodeInto(key + WS_GUID)
      const blob: cryptoFramework.DataBlob = { data: input }
      const md = cryptoFramework.createMd('SHA1')
      md.updateSync(blob)
      const out: cryptoFramework.DataBlob = md.digestSync()
      return new util.Base64Helper().encodeToStringSync(out.data)
    } catch (e) {
      console.error(`[${TAG}] computeAccept failed: ${JSON.stringify(e)}`)
      return ''
    }
  }

  // ---------- WS 帧消费 ----------

  private consumeFrames(conn: WsConnState): void {
    let guard = 0
    while (guard++ < 64) {
      const frame = this.tryParseFrame(conn.buffer)
      if (frame === null) {
        break // 未收齐，等待更多字节
      }
      conn.buffer = conn.buffer.subarray(frame.frameLength)
      this.onFrame(conn, frame)
      if (conn.closed) {
        return
      }
    }
  }

  private tryParseFrame(buf: Uint8Array): WsFrame | null {
    if (buf.length < 2) {
      return null
    }
    const b0 = buf[0]
    const b1 = buf[1]
    const fin = (b0 & 0x80) !== 0
    const opcode = b0 & 0x0F
    const masked = (b1 & 0x80) !== 0
    let len = b1 & 0x7F
    let off = 2
    if (len === 126) {
      if (buf.length < off + 2) {
        return null
      }
      len = (buf[off] << 8) | buf[off + 1]
      off += 2
    } else if (len === 127) {
      if (buf.length < off + 8) {
        return null
      }
      // uint64 高位必须为 0（超出 ArkTS number 安全整数即拒绝）
      for (let k = 0; k < 6; k++) {
        if (buf[off + k] !== 0) {
          console.error(`[${TAG}] frame length > 2^48, unsupported`)
          return null
        }
      }
      len = 0
      for (let k = 6; k < 8; k++) {
        len = len * 256 + buf[off + k]
      }
      off += 8
    }
    if (len > MAX_FRAME_PAYLOAD) {
      console.error(`[${TAG}] frame payload too large (${len}B)`)
      return null
    }
    if (!masked) {
      console.error(`[${TAG}] client frame without mask, protocol violation`)
      return null
    }
    if (buf.length < off + 4 + len) {
      return null
    }
    const mask = buf.subarray(off, off + 4)
    const payload = new Uint8Array(len)
    for (let i = 0; i < len; i++) {
      payload[i] = buf[off + 4 + i] ^ mask[i % 4]
    }
    const frame = new WsFrame()
    frame.fin = fin
    frame.opcode = opcode
    frame.payload = payload
    frame.frameLength = off + 4 + len
    return frame
  }

  private onFrame(conn: WsConnState, frame: WsFrame): void {
    if (frame.opcode === 0x1) { // text
      if (!frame.fin) {
        // continuation 分片：如实记录不支持——MCP JSON-RPC 消息单帧足够（帧上限 1MB）
        console.warn(`[${TAG}] fragmented text frame unsupported (len=${frame.payload.length}), ignoring`)
        return
      }
      const text = this.decodeUtf8(frame.payload)
      console.info(`[${TAG}] text frame id=${conn.client.clientId} len=${frame.payload.length}`)
      this.dispatchRpc(conn, text).catch((e: BusinessError) => {
        console.error(`[${TAG}] dispatch async error: ${e.code}/${e.message}`)
      })
    } else if (frame.opcode === 0x8) { // Close：回 Close 帧后断开清理
      console.info(`[${TAG}] close frame id=${conn.client.clientId}, echoing close`)
      const echo = frame.payload.subarray(0)
      this.sendControlFrame(conn, 0x8, echo).catch(() => {
      }).then(() => {
        this.closeConn(conn, -1, 'peer close')
      })
    } else if (frame.opcode === 0x9) { // Ping → Pong（心跳）
      console.info(`[${TAG}] ping id=${conn.client.clientId} -> pong`)
      this.sendControlFrame(conn, 0xA, frame.payload).catch(() => {
      })
    } else if (frame.opcode === 0xA) { // Pong → 忽略
    } else if (frame.opcode === 0x0) {
      // 无首片上下文的 continuation：如实记录不支持（见 0x1 分支注释）
      console.warn(`[${TAG}] standalone continuation frame ignored`)
    } else if (frame.opcode === 0x2) {
      console.warn(`[${TAG}] binary frame ignored (JSON-RPC only)`)
    } else {
      console.warn(`[${TAG}] unknown opcode 0x${frame.opcode.toString(16)} ignored`)
    }
  }

  // ---------- JSON-RPC 分发（与 HTTP 9222 同核 McpJsonRpcCore） ----------

  private async dispatchRpc(conn: WsConnState, text: string): Promise<void> {
    // P43b (KAI-047): 每连接滑动窗口限流（与 HTTP 传输同款语义）
    const rlKey = `ws_${conn.client.clientId}`
    const rl = McpRateLimiter.allow(rlKey)
    if (!rl.allowed) {
      console.warn(`[${TAG}] rate limited id=${conn.client.clientId} retryAfterMs=${rl.retryAfterMs}`)
      const errBody = `{"jsonrpc":"2.0","id":null,"error":{"code":-32000,"message":"rate limited","data":{"retryAfterMs":${rl.retryAfterMs}}}}`
      await this.sendTextFrame(conn, errBody)
      return
    }
    // P51: WS connection-bound session identity
    const outcome = await McpJsonRpcCore.handleRpc(text, conn.token, 'mcp_ws', conn.sessionId)
    if (outcome.sessionId !== '') {
      conn.sessionId = outcome.sessionId
      this.sessionConns.set(outcome.sessionId, conn)
      console.info(`[${TAG}] session bound id=${conn.client.clientId} session=${outcome.sessionId}`)
    }
    await this.sendTextFrame(conn, outcome.bodyText)
  }

  // ---------- 帧编码（服务器→客户端不掩码） ----------

  private async sendTextFrame(conn: WsConnState, text: string): Promise<void> {
    await this.sendWsFrame(conn, 0x1, new util.TextEncoder().encodeInto(text))
  }

  private async sendControlFrame(conn: WsConnState, opcode: number, payload: Uint8Array): Promise<void> {
    await this.sendWsFrame(conn, opcode, payload)
  }

  private async sendWsFrame(conn: WsConnState, opcode: number, payload: Uint8Array): Promise<void> {
    const header = new Uint8Array(10)
    let hLen = 0
    header[0] = 0x80 | opcode // FIN=1
    const len = payload.length
    if (len < 126) {
      header[1] = len
      hLen = 2
    } else if (len < 65536) {
      header[1] = 126
      header[2] = (len >> 8) & 0xFF
      header[3] = len & 0xFF
      hLen = 4
    } else {
      header[1] = 127
      // 8 字节大端长度（payload 上限 1MB → 高 4 字节恒 0，安全整数内）
      header[2] = 0
      header[3] = 0
      header[4] = 0
      header[5] = 0
      header[6] = (len >>> 24) & 0xFF
      header[7] = (len >>> 16) & 0xFF
      header[8] = (len >>> 8) & 0xFF
      header[9] = len & 0xFF
      hLen = 10
    }
    const out = new Uint8Array(hLen + payload.length)
    out.set(header.subarray(0, hLen), 0)
    out.set(payload, hLen)
    await this.sendRaw(conn, out)
  }

  private async sendRaw(conn: WsConnState, bytes: Uint8Array): Promise<void> {
    if (conn.closed) {
      return
    }
    const data = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length)
    try {
      await conn.client.send({ data: data })
    } catch (e) {
      const detail = (e as BusinessError).code !== undefined
        ? `${(e as BusinessError).code}/${(e as BusinessError).message}` : JSON.stringify(e)
      console.error(`[${TAG}] send failed client=${conn.client.clientId}: ${detail}`)
    }
  }

  // ---------- HTTP 拒绝响应（握手失败路径，发完即断） ----------

  private rejectHttp(conn: WsConnState, statusLine: string, bodyText: string): void {
    const bodyBytes = new util.TextEncoder().encodeInto(bodyText)
    const headText =
      `HTTP/1.1 ${statusLine}\r\n` +
      'Content-Type: application/json\r\n' +
      `Content-Length: ${bodyBytes.length}\r\n` +
      'Connection: close\r\n' +
      '\r\n'
    const headBytes = new util.TextEncoder().encodeInto(headText)
    const out = new Uint8Array(headBytes.length + bodyBytes.length)
    out.set(headBytes, 0)
    out.set(bodyBytes, headBytes.length)
    const data = out.buffer.slice(out.byteOffset, out.byteOffset + out.length)
    conn.client.send({ data: data }).catch(() => {
    }).then(() => {
      conn.client.close().catch(() => {
      })
    })
    conn.closed = true
    this.cleanupConn(conn)
  }

  private closeConn(conn: WsConnState, code: number, reason: string): void {
    if (conn.closed) {
      return
    }
    conn.closed = true
    if (code >= 0) {
      // 服务端主动 Close 帧：2B status code（大端）+ reason UTF-8
      const reasonBytes = new util.TextEncoder().encodeInto(reason)
      const payload = new Uint8Array(2 + reasonBytes.length)
      payload[0] = (code >> 8) & 0xFF
      payload[1] = code & 0xFF
      payload.set(reasonBytes, 2)
      this.sendControlFrame(conn, 0x8, payload).catch(() => {
      })
    }
    conn.client.close().catch(() => {
    })
    this.cleanupConn(conn)
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

export const WsMcpTransport = new WsMcpTransportImpl()
