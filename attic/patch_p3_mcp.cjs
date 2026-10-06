// P3 patch: MCPServer start/stop wire to HttpMcpTransport + McpHttpDelegate impl
const fs = require('fs')
const path = 'entry/src/main/ets/service/MCPServer.ets'
let s = fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n')
const orig = s

// 1) class implements delegate
if (!s.includes('implements McpHttpDelegate')) {
  s = s.replace('class MCPServerImpl {', 'class MCPServerImpl implements McpHttpDelegate {')
}

// 2) start(): wire transport
const oldStart = `  async start(port: number, authToken: string): Promise<boolean> {
    this.port = port
    this.authToken = authToken
    this.registerToolHandlers()

    try {
      this.running = true
      const startData: MCPConnectionChangeData = { status: 'started', port: this.port }
      EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, startData)
      return true
    } catch (e) {
      ErrorHandler.handle(new AppError(ErrorCodes.MCP_004, \`Port conflict: \${e}\`))
      this.port++
      return this.start(this.port, authToken)
    }
  }`
const newStart = `  async start(port: number, authToken: string): Promise<boolean> {
    this.port = port
    this.authToken = authToken
    this.registerToolHandlers()

    // P3: 真实网络层接线 —— HttpMcpTransport 监听 0.0.0.0:{port}（失败即返回，不再盲重试端口）
    const listening = await HttpMcpTransport.start(port, this)
    if (!listening) {
      ErrorHandler.handle(new AppError(ErrorCodes.MCP_004, \`Port \${port} unavailable\`))
      return false
    }

    this.running = true
    const startData: MCPConnectionChangeData = { status: 'started', port: this.port }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, startData)
    console.info('[MCPServer] started, HTTP transport listening on 0.0.0.0:' + this.port)
    return true
  }`
if (s.includes(oldStart)) {
  s = s.replace(oldStart, newStart)
} else {
  console.error('FAIL: start() anchor not found'); process.exit(1)
}

// 3) stop(): release transport
const oldStop = `  async stop(): Promise<void> {
    this.running = false
    this.connections.clear()
    const stopData: MCPConnectionChangeData = { status: 'stopped', port: this.port }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, stopData)
  }`
const newStop = `  async stop(): Promise<void> {
    await HttpMcpTransport.stop()
    this.running = false
    this.connections.clear()
    const stopData: MCPConnectionChangeData = { status: 'stopped', port: this.port }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, stopData)
  }`
if (s.includes(oldStop)) {
  s = s.replace(oldStop, newStop)
} else {
  console.error('FAIL: stop() anchor not found'); process.exit(1)
}

// 4) McpHttpDelegate impl: getToolNames (getAvailableTools already exists & signature matches)
if (!s.includes('getToolNames')) {
  const anchor = `  getAvailableTools(): string[] {
    return Array.from(this.toolHandlers.keys())
  }`
  const repl = anchor + `

  /** P3: McpHttpDelegate —— 供 HTTP 层拉取工具名列表 */
  getToolNames(): string[] {
    return Array.from(this.toolHandlers.keys())
  }`
  if (s.includes(anchor)) {
    s = s.replace(anchor, repl)
  } else {
    console.error('FAIL: getAvailableTools anchor not found'); process.exit(1)
  }
}

fs.writeFileSync(path, s.replace(/\n/g, '\r\n'))
console.log('OK: MCPServer patched, delta=' + (s.length - orig.length))
