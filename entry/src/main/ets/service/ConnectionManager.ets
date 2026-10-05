import { MCPConnection, MCPConnectionJSON } from '../model/MCPConnection'
import { ConnectionStatus, ToolType } from '../common/Types'
import { MCPServer } from './MCPServer'
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'

interface AIToolInfo {
  name: string
  displayName: string
  configFilePath: string
  detected: boolean
  connected: boolean
}

interface ConnectionEventData {
  status: string
  toolName?: string
  endpoint?: string
  connectionId?: string
}

interface ConnectionsPersistData {
  connections: MCPConnectionJSON[]
}

class ConnectionManagerImpl {
  private connections: Map<string, MCPConnection> = new Map()
  private knownTools: AIToolInfo[] = [
    {
      name: 'claude-code',
      displayName: 'Claude Code',
      configFilePath: '~/.claude.json',
      detected: false,
      connected: false
    },
    {
      name: 'codex',
      displayName: 'Codex',
      configFilePath: '~/.codex/config.json',
      detected: false,
      connected: false
    },
    {
      name: 'cursor',
      displayName: 'Cursor',
      configFilePath: '~/.cursor/config.json',
      detected: false,
      connected: false
    },
    {
      name: 'vscode',
      displayName: 'VS Code',
      configFilePath: '~/.vscode/settings.json',
      detected: false,
      connected: false
    },
    {
      name: 'openclaw',
      displayName: 'OpenClaw',
      configFilePath: '~/.openclaw/config.json',
      detected: false,
      connected: false
    },
    {
      name: 'hermes',
      displayName: 'Hermes',
      configFilePath: '~/.hermes/config.json',
      detected: false,
      connected: false
    }
  ]

  detectInstalledTools(): AIToolInfo[] {
    for (const tool of this.knownTools) {
      tool.detected = this.checkToolInstalled(tool.name)
    }

    const detected = this.knownTools.filter(t => t.detected)
    if (detected.length === 0) {
      const noToolsData: ConnectionEventData = { status: 'no_tools_detected' }
      EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, noToolsData)
    }

    return detected
  }

  async connect(toolName: string): Promise<MCPConnection | null> {
    const tool = this.knownTools.find(t => t.name === toolName)
    if (!tool || !tool.detected) {
      ErrorHandler.handle(new AppError(ErrorCodes.CON_001, `Tool not detected: ${toolName}`))
      return null
    }

    const authToken = MCPServer.generateAuthToken()
    const port = MCPServer.getPort()
    const endpoint = `http://127.0.0.1:${port}`
    const connectionId = this.generateConnectionId()

    const connection = new MCPConnection(connectionId, endpoint, authToken)

    const configWritten = await this.writeMCPConfig(tool, endpoint, authToken)
    if (!configWritten) {
      ErrorHandler.handle(new AppError(ErrorCodes.CON_002, `Config write failed for ${toolName}`))
      return null
    }

    connection.connect()
    this.connections.set(connectionId, connection)
    tool.connected = true

    const connectedData: ConnectionEventData = {
      status: 'connected',
      toolName: toolName,
      endpoint: endpoint,
      connectionId: connectionId
    }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, connectedData)

    return connection
  }

  async disconnect(connectionId: string): Promise<boolean> {
    const connection = this.connections.get(connectionId)
    if (!connection) {
      return false
    }

    connection.disconnect()
    this.connections.delete(connectionId)

    for (const tool of this.knownTools) {
      if (tool.connected && connection.endpoint.includes(MCPServer.getPort().toString())) {
        tool.connected = false
      }
    }

    const disconnectedData: ConnectionEventData = {
      status: 'disconnected',
      connectionId: connectionId
    }
    EventBus.emit(EventBusEvents.MCP_CONNECTION_CHANGE, disconnectedData)

    return true
  }

  getConnectionStatus(connectionId: string): ConnectionStatus {
    const connection = this.connections.get(connectionId)
    if (!connection) {
      return ConnectionStatus.DISCONNECTED
    }
    return connection.status
  }

  getAllConnections(): MCPConnection[] {
    return Array.from(this.connections.values())
  }

  getConnectedTools(): AIToolInfo[] {
    return this.knownTools.filter(t => t.connected)
  }

  getDetectedTools(): AIToolInfo[] {
    return this.knownTools.filter(t => t.detected)
  }

  generateMCPConfigJSON(endpoint: string, authToken: string): string {
    const url = `${endpoint}/sse?token=${authToken}`
    return `{"mcpServers":{"browseros-kaihongos":{"url":"${url}","transport":"sse"}}}`
  }

  private checkToolInstalled(toolName: string): boolean {
    return false
  }

  private async writeMCPConfig(tool: AIToolInfo, endpoint: string, authToken: string): Promise<boolean> {
    const configJson = this.generateMCPConfigJSON(endpoint, authToken)

    try {
      const configPath = `connections/${tool.name}_mcp.json`
      return await StorageManager.save(configPath, configJson)
    } catch (e) {
      return false
    }
  }

  private generateConnectionId(): string {
    return `conn_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`
  }

  async persistConnections(): Promise<void> {
    const connectionsArray: MCPConnectionJSON[] = []
    this.connections.forEach((conn: MCPConnection, id: string) => {
      connectionsArray.push(conn.toJSON())
    })
    const data: ConnectionsPersistData = { connections: connectionsArray }
    await StorageManager.saveJSON('connections.json', data)
  }

  async loadConnections(): Promise<void> {
    const json = await StorageManager.loadJSON('connections.json')
    if (json) {
      const connectionsArray = json['connections'] as Record<string, Object>[]
      for (const connJson of connectionsArray) {
        const conn = MCPConnection.fromJSON(connJson)
        this.connections.set(conn.connectionId, conn)
      }
    }
  }
}

export const ConnectionManager = new ConnectionManagerImpl()