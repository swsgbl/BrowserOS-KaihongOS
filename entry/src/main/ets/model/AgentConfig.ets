import { RunStrategy } from '../common/Types'

interface AgentConfigJSON {
  agentId: string
  name: string
  targetUrl: string
  taskDescription: string
  runStrategy: RunStrategy
  createdAt: number
  tabId: string
}

export class AgentConfig {
  agentId: string = ''
  name: string = ''
  targetUrl: string = ''
  taskDescription: string = ''
  runStrategy: RunStrategy = RunStrategy.ONCE
  createdAt: number = 0
  tabId: string = ''

  constructor(agentId: string, name: string, targetUrl: string, taskDescription: string,
    runStrategy: RunStrategy, createdAt: number, tabId: string) {
    this.agentId = agentId
    this.name = name
    this.targetUrl = targetUrl
    this.taskDescription = taskDescription
    this.runStrategy = runStrategy
    this.createdAt = createdAt
    this.tabId = tabId
  }

  toJSON(): AgentConfigJSON {
    const result: AgentConfigJSON = {
      agentId: this.agentId,
      name: this.name,
      targetUrl: this.targetUrl,
      taskDescription: this.taskDescription,
      runStrategy: this.runStrategy,
      createdAt: this.createdAt,
      tabId: this.tabId
    }
    return result
  }

  static fromJSON(json: AgentConfigJSON): AgentConfig {
    return new AgentConfig(
      json.agentId,
      json.name,
      json.targetUrl,
      json.taskDescription,
      json.runStrategy,
      json.createdAt,
      json.tabId
    )
  }
}