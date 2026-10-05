import { RecordingQuality } from '../common/Types'

interface AppConfigJSON {
  mcpPort: number
  maxAgents: number
  recordingQuality: RecordingQuality
  recordingMaxSpaceMb: number
  snapshotCompressionRatio: number
  agentTimeoutMinutes: number
  mcpReconnectMaxAttempts: number
  mcpReconnectIntervalMs: number
  pageLoadTimeoutMs: number
  bcpOperationTimeoutMs: number
  heartbeatIntervalMs: number
  dashboardRefreshIntervalMs: number
  virtualListThreshold: number
  isOnboardingCompleted: boolean
  isNeoMode: boolean
  telemetryEnabled: boolean
}

export interface AppConfigUpdate {
  mcpPort?: number
  maxAgents?: number
  recordingQuality?: RecordingQuality
  recordingMaxSpaceMb?: number
  snapshotCompressionRatio?: number
  agentTimeoutMinutes?: number
  isOnboardingCompleted?: boolean
  isNeoMode?: boolean
  telemetryEnabled?: boolean
}

export class AppConfig {
  mcpPort: number = 9222
  maxAgents: number = 5
  recordingQuality: RecordingQuality = RecordingQuality.MEDIUM
  recordingMaxSpaceMb: number = 500
  snapshotCompressionRatio: number = 0.3
  agentTimeoutMinutes: number = 5
  mcpReconnectMaxAttempts: number = 3
  mcpReconnectIntervalMs: number = 3000
  pageLoadTimeoutMs: number = 15000
  bcpOperationTimeoutMs: number = 10000
  heartbeatIntervalMs: number = 1000
  dashboardRefreshIntervalMs: number = 1000
  virtualListThreshold: number = 20
  isOnboardingCompleted: boolean = false
  isNeoMode: boolean = false
  telemetryEnabled: boolean = false

  toJSON(): AppConfigJSON {
    const result: AppConfigJSON = {
      mcpPort: this.mcpPort,
      maxAgents: this.maxAgents,
      recordingQuality: this.recordingQuality,
      recordingMaxSpaceMb: this.recordingMaxSpaceMb,
      snapshotCompressionRatio: this.snapshotCompressionRatio,
      agentTimeoutMinutes: this.agentTimeoutMinutes,
      mcpReconnectMaxAttempts: this.mcpReconnectMaxAttempts,
      mcpReconnectIntervalMs: this.mcpReconnectIntervalMs,
      pageLoadTimeoutMs: this.pageLoadTimeoutMs,
      bcpOperationTimeoutMs: this.bcpOperationTimeoutMs,
      heartbeatIntervalMs: this.heartbeatIntervalMs,
      dashboardRefreshIntervalMs: this.dashboardRefreshIntervalMs,
      virtualListThreshold: this.virtualListThreshold,
      isOnboardingCompleted: this.isOnboardingCompleted,
      isNeoMode: this.isNeoMode,
      telemetryEnabled: this.telemetryEnabled
    }
    return result
  }

  static fromJSON(json: Record<string, Object>): AppConfig {
    const config = new AppConfig()
    config.mcpPort = json['mcpPort'] as number
    config.maxAgents = json['maxAgents'] as number
    config.recordingQuality = json['recordingQuality'] as RecordingQuality
    config.recordingMaxSpaceMb = json['recordingMaxSpaceMb'] as number
    config.snapshotCompressionRatio = json['snapshotCompressionRatio'] as number
    config.agentTimeoutMinutes = json['agentTimeoutMinutes'] as number
    config.mcpReconnectMaxAttempts = json['mcpReconnectMaxAttempts'] as number
    config.mcpReconnectIntervalMs = json['mcpReconnectIntervalMs'] as number
    config.pageLoadTimeoutMs = json['pageLoadTimeoutMs'] as number
    config.bcpOperationTimeoutMs = json['bcpOperationTimeoutMs'] as number
    config.heartbeatIntervalMs = json['heartbeatIntervalMs'] as number
    config.dashboardRefreshIntervalMs = json['dashboardRefreshIntervalMs'] as number
    config.virtualListThreshold = json['virtualListThreshold'] as number
    config.isOnboardingCompleted = json['isOnboardingCompleted'] as boolean
    config.isNeoMode = json['isNeoMode'] as boolean
    config.telemetryEnabled = json['telemetryEnabled'] as boolean
    return config
  }

  static getDefault(): AppConfig {
    return new AppConfig()
  }

  validate(): string[] {
    const errors: string[] = []
    if (this.mcpPort < 1024 || this.mcpPort > 65535) {
      errors.push('mcpPort must be between 1024 and 65535')
    }
    if (this.maxAgents < 1 || this.maxAgents > 20) {
      errors.push('maxAgents must be between 1 and 20')
    }
    if (this.snapshotCompressionRatio < 0.1 || this.snapshotCompressionRatio > 0.5) {
      errors.push('snapshotCompressionRatio must be between 0.1 and 0.5')
    }
    if (this.recordingMaxSpaceMb < 100 || this.recordingMaxSpaceMb > 5000) {
      errors.push('recordingMaxSpaceMb must be between 100 and 5000')
    }
    return errors
  }
}