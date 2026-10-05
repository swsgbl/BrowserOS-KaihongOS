import { ToolType, ConnectionStatus } from '../common/Types'

export interface MCPConnectionJSON {
  connectionId: string
  toolType: ToolType
  endpoint: string
  authToken: string
  status: ConnectionStatus
  connectTime: number
  disconnectTime: number
}

export class MCPConnection {
  connectionId: string = ''
  toolType: ToolType = ToolType.NAVIGATE
  endpoint: string = ''
  authToken: string = ''
  status: ConnectionStatus = ConnectionStatus.DISCONNECTED
  connectTime: number = 0
  disconnectTime: number = 0

  constructor(connectionId: string, endpoint: string, authToken: string) {
    this.connectionId = connectionId
    this.endpoint = endpoint
    this.authToken = authToken
  }

  connect(): void {
    this.status = ConnectionStatus.CONNECTED
    this.connectTime = Date.now()
  }

  disconnect(): void {
    this.status = ConnectionStatus.DISCONNECTED
    this.disconnectTime = Date.now()
  }

  toJSON(): MCPConnectionJSON {
    const result: MCPConnectionJSON = {
      connectionId: this.connectionId,
      toolType: this.toolType,
      endpoint: this.endpoint,
      authToken: this.authToken,
      status: this.status,
      connectTime: this.connectTime,
      disconnectTime: this.disconnectTime
    }
    return result
  }

  static fromJSON(json: Record<string, Object>): MCPConnection {
    const conn = new MCPConnection(
      json['connectionId'] as string,
      json['endpoint'] as string,
      json['authToken'] as string
    )
    conn.toolType = json['toolType'] as ToolType
    conn.status = json['status'] as ConnectionStatus
    conn.connectTime = json['connectTime'] as number
    conn.disconnectTime = json['disconnectTime'] as number
    return conn
  }
}