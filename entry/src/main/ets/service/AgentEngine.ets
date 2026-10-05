import { AgentConfig } from '../model/AgentConfig'
import { AgentStatusInfo } from '../model/AgentStatus'
import { AgentStatus, RunStrategy } from '../common/Types'
import { TabManager } from './TabManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { ConfigManager } from '../storage/ConfigManager'

type StatusChangeCallback = (agentId: string, status: AgentStatus) => void

interface AgentTimeoutErrorData {
  code: string
  message: string
  agentId: string
}

class AgentEngineImpl {
  private agents: Map<string, AgentConfig> = new Map()
  private agentStatuses: Map<string, AgentStatusInfo> = new Map()
  private statusCallbacks: StatusChangeCallback[] = []
  private heartbeatTimers: Map<string, number> = new Map()
  private timeoutTimers: Map<string, number> = new Map()

  createAgent(name: string, targetUrl: string, taskDescription: string,
    runStrategy: RunStrategy = RunStrategy.ONCE): AgentConfig | null {
    const maxAgents = ConfigManager.getMaxAgents()
    if (this.agents.size >= maxAgents) {
      ErrorHandler.handle(new AppError(ErrorCodes.AGT_001, `Max agents (${maxAgents}) reached`))
      return null
    }

    const agentId = this.generateAgentId()
    const tab = TabManager.createAgentTab(agentId)
    const config = new AgentConfig(agentId, name, targetUrl, taskDescription, runStrategy, Date.now(), tab.tabId)
    const status = new AgentStatusInfo(agentId)

    this.agents.set(agentId, config)
    this.agentStatuses.set(agentId, status)

    EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())

    this.startHeartbeat(agentId)

    return config
  }

  terminateAgent(agentId: string): boolean {
    const config = this.agents.get(agentId)
    if (!config) {
      ErrorHandler.handle(new AppError(ErrorCodes.AGT_002, `Agent not found: ${agentId}`))
      return false
    }

    this.stopHeartbeat(agentId)
    this.stopTimeoutTimer(agentId)

    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.STOPPED)
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.STOPPED)
    }

    TabManager.closeTab(config.tabId)

    this.agents.delete(agentId)
    this.agentStatuses.delete(agentId)

    return true
  }

  getAgentStatus(agentId: string): AgentStatusInfo | null {
    return this.agentStatuses.get(agentId) || null
  }

  getAllAgentStatus(): AgentStatusInfo[] {
    return Array.from(this.agentStatuses.values())
  }

  getAgentConfig(agentId: string): AgentConfig | null {
    return this.agents.get(agentId) || null
  }

  getAllAgents(): AgentConfig[] {
    return Array.from(this.agents.values())
  }

  resetAgent(agentId: string): boolean {
    const config = this.agents.get(agentId)
    if (!config) {
      return false
    }

    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.IDLE)
      status.currentUrl = ''
      status.progress = 0
      status.errorMessage = ''
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.IDLE)
    }

    return true
  }

  onStatusChange(callback: StatusChangeCallback): void {
    this.statusCallbacks.push(callback)
  }

  removeStatusChangeCallback(callback: StatusChangeCallback): void {
    const idx = this.statusCallbacks.indexOf(callback)
    if (idx >= 0) {
      this.statusCallbacks.splice(idx, 1)
    }
  }

  setAgentRunning(agentId: string): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.RUNNING)
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.RUNNING)
      this.startTimeoutTimer(agentId)
    }
  }

  setAgentCompleted(agentId: string): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.COMPLETED)
      status.progress = 100
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.COMPLETED)
      this.stopTimeoutTimer(agentId)
    }
  }

  setAgentError(agentId: string, errorMessage: string): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.ERROR)
      status.errorMessage = errorMessage
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.ERROR)
      this.stopTimeoutTimer(agentId)
    }
  }

  setAgentPaused(agentId: string): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.updateStatus(AgentStatus.PAUSED)
      EventBus.emit(EventBusEvents.AGENT_STATUS_CHANGE, status.toJSON())
      this.notifyStatusChange(agentId, AgentStatus.PAUSED)
    }
  }

  updateAgentProgress(agentId: string, progress: number, currentUrl: string = ''): void {
    const status = this.agentStatuses.get(agentId)
    if (status) {
      status.progress = progress
      if (currentUrl) {
        status.currentUrl = currentUrl
      }
      EventBus.emit(EventBusEvents.AGENT_HEARTBEAT, status.toJSON())
    }
  }

  getAgentCount(): number {
    return this.agents.size
  }

  getRunningAgentCount(): number {
    let count = 0
    for (const status of this.agentStatuses.values()) {
      if (status.status === AgentStatus.RUNNING) {
        count++
      }
    }
    return count
  }

  private startHeartbeat(agentId: string): void {
    const intervalId = setInterval(() => {
      const status = this.agentStatuses.get(agentId)
      if (status && status.status === AgentStatus.RUNNING) {
        status.updateHeartbeat()
        EventBus.emit(EventBusEvents.AGENT_HEARTBEAT, status.toJSON())
      }
    }, Constants.HEARTBEAT_INTERVAL_MS)
    this.heartbeatTimers.set(agentId, intervalId)
  }

  private stopHeartbeat(agentId: string): void {
    const timer = this.heartbeatTimers.get(agentId)
    if (timer) {
      clearInterval(timer)
      this.heartbeatTimers.delete(agentId)
    }
  }

  private startTimeoutTimer(agentId: string): void {
    const timeoutMs = ConfigManager.get().agentTimeoutMinutes * 60 * 1000
    const timerId = setTimeout(() => {
      const status = this.agentStatuses.get(agentId)
      if (status && status.status === AgentStatus.RUNNING) {
        this.setAgentPaused(agentId)
        const errorData: AgentTimeoutErrorData = {
          code: ErrorCodes.AGT_005,
          message: ErrorCodes.getMessage(ErrorCodes.AGT_005),
          agentId: agentId
        }
        EventBus.emit(EventBusEvents.ERROR_OCCURRED, errorData)
      }
    }, timeoutMs)
    this.timeoutTimers.set(agentId, timerId)
  }

  private stopTimeoutTimer(agentId: string): void {
    const timer = this.timeoutTimers.get(agentId)
    if (timer) {
      clearTimeout(timer)
      this.timeoutTimers.delete(agentId)
    }
  }

  private notifyStatusChange(agentId: string, status: AgentStatus): void {
    for (const callback of this.statusCallbacks) {
      try {
        callback(agentId, status)
      } catch (e) {
        console.error(`Status change callback error: ${e}`)
      }
    }
  }

  private generateAgentId(): string {
    return `agent_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`
  }

  terminateAll(): void {
    for (const agentId of Array.from(this.agents.keys())) {
      this.terminateAgent(agentId)
    }
  }
}

export const AgentEngine = new AgentEngineImpl()