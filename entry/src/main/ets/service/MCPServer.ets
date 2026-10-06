import { BCPResult, MCPToolResponse, ToolType } from '../common/Types'
import { BCPEngine } from '../protocol/BCPEngine'
import { SnapshotGenerator } from '../protocol/SnapshotGenerator'
import { ScreenshotCapture } from '../protocol/ScreenshotCapture'
import { AgentEngine } from './AgentEngine'
import { SensitiveOperationDetector } from './SensitiveOperationDetector'
import { AuditLogger } from '../storage/AuditLogger'
import { AuditLogEntry } from '../model/AuditLogEntry'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { SensitiveOperationType } from '../common/Types'
import { HttpMcpTransport, McpHttpDelegate } from './HttpMcpTransport'
import { StorageManager } from '../storage/StorageManager'

type ToolHandler = (params: Record<string, Object>, agentId: string) => Promise<MCPToolResponse>

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
  selector?: string
  text?: string
  quality?: string
  deltaX?: number
  deltaY?: number
  ms?: number
  timeout?: number
  result?: string | null
}

class MCPServerImpl implements McpHttpDelegate {
  private port: number = Constants.DEFAULT_MCP_PORT
  private authToken: string = ''
  private running: boolean = false
  private toolHandlers: Map<string, ToolHandler> = new Map()
  private connections: Set<string> = new Set()

  async start(port: number, authToken: string): Promise<boolean> {
    this.port = port
    this.authToken = authToken
    this.registerToolHandlers()

    // P3: 真实网络层接线 —— HttpMcpTransport 监听 0.0.0.0:{port}（失败即返回，不再盲重试端口）
    const listening = await HttpMcpTransport.start(port, this)
    if (!listening) {
      ErrorHandler.handle(new AppError(ErrorCodes.MCP_004, `Port ${port} unavailable`))
      return false
    }

    this.running = true
    const startData: MCPConnectionChangeData = { status: 'started', port: this.port }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, startData)
    console.info('[MCPServer] started, HTTP transport listening on 0.0.0.0:' + this.port)

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
    token: string): Promise<MCPToolResponse> {
    if (!this.validateToken(token)) {
      return {
        status: 'error',
        data: null,
        error: ErrorCodes.getMessage(ErrorCodes.MCP_001),
        requestId: this.generateRequestId()
      }
    }

    const handler = this.toolHandlers.get(toolName)
    if (!handler) {
      return {
        status: 'error',
        data: null,
        error: ErrorCodes.getMessage(ErrorCodes.MCP_002),
        requestId: this.generateRequestId()
      }
    }

    const requestId = this.generateRequestId()
    const auditEntry = new AuditLogEntry(requestId, agentId, toolName, params['url'] as string || '')

    const callData: MCPToolCallData = { requestId: requestId, agentId: agentId, toolName: toolName, params: params }
    EventBus.emit(EventBusEvents.MCP_TOOL_CALL, callData)

    try {
      const response = await handler(params, agentId)
      auditEntry.setResult(response.status, response.error || '')
      AuditLogger.log(auditEntry)
      const responseData: MCPToolResponseEventData = { requestId: requestId, response: response }
      EventBus.emit(EventBusEvents.MCP_TOOL_RESPONSE, responseData)
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
    this.toolHandlers.set(ToolType.NAVIGATE, this.handleNavigate)
    this.toolHandlers.set(ToolType.CLICK, this.handleClick)
    this.toolHandlers.set(ToolType.TYPE, this.handleType)
    this.toolHandlers.set(ToolType.SCREENSHOT, this.handleScreenshot)
    this.toolHandlers.set(ToolType.SNAPSHOT, this.handleSnapshot)
    this.toolHandlers.set(ToolType.SCROLL, this.handleScroll)
    this.toolHandlers.set(ToolType.GET_TEXT, this.handleGetText)
    this.toolHandlers.set(ToolType.WAIT, this.handleWait)
    this.toolHandlers.set(ToolType.BACK, this.handleBack)
    this.toolHandlers.set(ToolType.FORWARD, this.handleForward)
  }

  private handleNavigate: ToolHandler = async (params, agentId) => {
    const url = params['url'] as string
    if (!url) {
      return this.errorResponse(ErrorCodes.MCP_003, 'Missing url parameter')
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
    const data: MCPResponseData = { url: url, result: result.data }
    return this.bcpToMcpResponse(result, data)
  }

  private handleClick: ToolHandler = async (params, agentId) => {
    const selector = params['selector'] as string
    if (!selector) {
      return this.errorResponse(ErrorCodes.MCP_003, 'Missing selector parameter')
    }

    const sensitiveType = SensitiveOperationDetector.detectClick(agentId, selector, params['text'] as string || '')
    if (sensitiveType) {
      const confirmed = await SensitiveOperationDetector.requestConfirmation(
        agentId, sensitiveType, '', selector)
      if (!confirmed) {
        return this.errorResponse(ErrorCodes.AGT_003, 'Operation rejected by user')
      }
    }

    const result = await BCPEngine.click(selector)
    const data: MCPResponseData = { selector: selector, result: result.data }
    return this.bcpToMcpResponse(result, data)
  }

  private handleType: ToolHandler = async (params, agentId) => {
    const selector = params['selector'] as string
    const text = params['text'] as string
    if (!selector || text === undefined) {
      return this.errorResponse(ErrorCodes.MCP_003, 'Missing selector or text parameter')
    }

    const result = await BCPEngine.type(selector, text)
    const data: MCPResponseData = { selector: selector, text: text, result: result.data }
    return this.bcpToMcpResponse(result, data)
  }

  private handleScreenshot: ToolHandler = async (params, agentId) => {
    const quality = params['quality'] as string || 'medium'
    const result = await ScreenshotCapture.capture(quality)
    const data: MCPResponseData = { quality: quality, result: result.data }
    return this.bcpToMcpResponse(result, data)
  }

  private handleSnapshot: ToolHandler = async (params, agentId) => {
    const result = await SnapshotGenerator.generate()
    const data: MCPResponseData = { result: result.data }
    return this.bcpToMcpResponse(result, data)
  }

  private handleScroll: ToolHandler = async (params, agentId) => {
    const deltaX = params['deltaX'] as number || 0
    const deltaY = params['deltaY'] as number || 0
    const result = await BCPEngine.scroll(deltaX, deltaY)
    const data: MCPResponseData = { deltaX: deltaX, deltaY: deltaY, result: result.data }
    return this.bcpToMcpResponse(result, data)
  }

  private handleGetText: ToolHandler = async (params, agentId) => {
    const result = await BCPEngine.getText()
    const data: MCPResponseData = { result: result.data }
    return this.bcpToMcpResponse(result, data)
  }

  private handleWait: ToolHandler = async (params, agentId) => {
    const ms = params['ms'] as number
    const selector = params['selector'] as string

    if (selector) {
      const timeout = params['timeout'] as number || 5000
      const result = await BCPEngine.waitForElement(selector, timeout)
      const data: MCPResponseData = { selector: selector, timeout: timeout, result: result.data }
      return this.bcpToMcpResponse(result, data)
    } else if (ms) {
      const result = await BCPEngine.wait(ms)
      const data: MCPResponseData = { ms: ms, result: result.data }
      return this.bcpToMcpResponse(result, data)
    } else {
      return this.errorResponse(ErrorCodes.MCP_003, 'Missing ms or selector parameter')
    }
  }

  private handleBack: ToolHandler = async (params, agentId) => {
    const result = await BCPEngine.back()
    const data: MCPResponseData = { result: result.data }
    return this.bcpToMcpResponse(result, data)
  }

  private handleForward: ToolHandler = async (params, agentId) => {
    const result = await BCPEngine.forward()
    const data: MCPResponseData = { result: result.data }
    return this.bcpToMcpResponse(result, data)
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
    return `req_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`
  }

  generateAuthToken(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    let token = ''
    for (let i = 0; i < Constants.AUTH_TOKEN_LENGTH; i++) {
      token += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return token
  }
}

export const MCPServer = new MCPServerImpl()