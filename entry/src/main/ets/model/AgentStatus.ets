import { AgentStatus } from '../common/Types'

interface AgentStatusJSON {
  agentId: string
  status: AgentStatus
  currentUrl: string
  runningDuration: number
  progress: number
  errorMessage: string
  lastHeartbeat: number
}

export class AgentStatusInfo {
  agentId: string = ''
  status: AgentStatus = AgentStatus.IDLE
  currentUrl: string = ''
  runningDuration: number = 0
  progress: number = 0
  errorMessage: string = ''
  lastHeartbeat: number = 0

  constructor(agentId: string) {
    this.agentId = agentId
    this.status = AgentStatus.IDLE
    this.lastHeartbeat = Date.now()
  }

  updateStatus(status: AgentStatus): void {
    this.status = status
    this.lastHeartbeat = Date.now()
  }

  updateHeartbeat(): void {
    this.runningDuration = Date.now() - this.lastHeartbeat
    this.lastHeartbeat = Date.now()
  }

  toJSON(): AgentStatusJSON {
    const result: AgentStatusJSON = {
      agentId: this.agentId,
      status: this.status,
      currentUrl: this.currentUrl,
      runningDuration: this.runningDuration,
      progress: this.progress,
      errorMessage: this.errorMessage,
      lastHeartbeat: this.lastHeartbeat
    }
    return result
  }

  static fromJSON(json: AgentStatusJSON): AgentStatusInfo {
    const info = new AgentStatusInfo(json.agentId)
    info.status = json.status
    info.currentUrl = json.currentUrl
    info.runningDuration = json.runningDuration
    info.progress = json.progress
    info.errorMessage = json.errorMessage
    info.lastHeartbeat = json.lastHeartbeat
    return info
  }
}