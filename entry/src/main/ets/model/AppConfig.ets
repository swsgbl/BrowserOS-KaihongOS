import { RecordingQuality } from '../common/Types'

interface AppConfigJSON {
  mcpPort: number
  wsPort: number
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
  darkMode: boolean
  sensitiveConfirm: boolean
  llmBaseUrl: string
  llmApiKey: string
  llmModel: string
  searchEngineId: string
  llmProviders: string
  updateSourcePref: string
}

export interface AppConfigUpdate {
  llmProviders?: string
  updateSourcePref?: string
  mcpPort?: number
  maxAgents?: number
  recordingQuality?: RecordingQuality
  recordingMaxSpaceMb?: number
  snapshotCompressionRatio?: number
  agentTimeoutMinutes?: number
  isOnboardingCompleted?: boolean
  isNeoMode?: boolean
  telemetryEnabled?: boolean
  darkMode?: boolean
  sensitiveConfirm?: boolean
  llmBaseUrl?: string
  llmApiKey?: string
  llmModel?: string
  searchEngineId?: string
}

/** P35/P36: llmProviders 预设条目（[{name,baseUrl,apiKey,model}]） */
interface LlmProviderItem {
  name: string
  baseUrl: string
  apiKey: string
  model: string
}

export class AppConfig {
  mcpPort: number = 9222
  wsPort: number = 8765
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
  darkMode: boolean = false
  sensitiveConfirm: boolean = true
  llmBaseUrl: string = ''
  llmApiKey: string = ''
  llmModel: string = ''
  searchEngineId: string = 'google'
  /** P69: 更新源偏好 auto|cn|global（auto=双源竞速） */
  updateSourcePref: string = 'auto'
  /** p23b: LLM 供应商预设列表 JSON（[{name,baseUrl,apiKey,model}]），空串=无预设 */
  llmProviders: string = ''

  /** P36: 脱敏出口 —— 密钥不落盘（llmApiKey 空 + providers keys 脱空），asset 持真值 */
  toJSON(): AppConfigJSON {
    return this.buildJSON(false)
  }

  /** P36: 明文出口 —— 仅 ConfigManager 降级模式（asset 不可用）落盘使用 */
  toJSONPlain(): AppConfigJSON {
    return this.buildJSON(true)
  }

  private buildJSON(keepSecrets: boolean): AppConfigJSON {
    const result: AppConfigJSON = {
      mcpPort: this.mcpPort,
      wsPort: this.wsPort,
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
      telemetryEnabled: this.telemetryEnabled,
      darkMode: this.darkMode,
      sensitiveConfirm: this.sensitiveConfirm,
      llmBaseUrl: this.llmBaseUrl,
      llmApiKey: keepSecrets ? this.llmApiKey : '',
      llmModel: this.llmModel,
      searchEngineId: this.searchEngineId,
      llmProviders: keepSecrets ? this.llmProviders : this.sanitizedProvidersForDisk(),
      updateSourcePref: this.updateSourcePref
    }
    return result
  }

  /** P36: 密钥指纹（前4后4，中段***）——写日志/比对用，永不回传全值 */
  static keyFingerprint(key: string): string {
    if (key.length === 0) {
      return '(empty)'
    }
    if (key.length <= 8) {
      return key.length + 'chars***'
    }
    return key.substring(0, 4) + '***' + key.substring(key.length - 4) + ' (' + key.length + 'ch)'
  }

  /** P36: llmProviders JSON 内每项 apiKey 脱空后序列化（异常原样返回） */
  private sanitizedProvidersForDisk(): string {
    if (this.llmProviders.length === 0) {
      return this.llmProviders
    }
    try {
      const arr = JSON.parse(this.llmProviders) as LlmProviderItem[]
      if (!Array.isArray(arr)) {
        return this.llmProviders
      }
      for (const it of arr) {
        it.apiKey = ''
      }
      return JSON.stringify(arr)
    } catch (e) {
      return this.llmProviders
    }
  }

  static fromJSON(json: Record<string, Object>): AppConfig {
    const config = new AppConfig()
    config.mcpPort = json['mcpPort'] as number
    // p13: tolerant read — old config.json without wsPort keeps default 8765
    config.wsPort = json['wsPort'] !== undefined && json['wsPort'] !== null ? json['wsPort'] as number : 8765
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
    config.telemetryEnabled = json['telemetryEnabled'] === true
    // p10: tolerant reads — old config.json without these fields keeps defaults
    config.darkMode = json['darkMode'] === true
    config.sensitiveConfirm = json['sensitiveConfirm'] !== false
    config.llmBaseUrl = AppConfig.sanitizeLlmBaseUrl((json['llmBaseUrl'] as string) || '')
    config.llmApiKey = (json['llmApiKey'] as string) || ''
    config.llmModel = (json['llmModel'] as string) || ''
    // p18: tolerant read — old config.json without searchEngineId keeps default 'google'
    config.searchEngineId = json['searchEngineId'] !== undefined && json['searchEngineId'] !== null ? json['searchEngineId'] as string : 'google'
    // p23b: tolerant read — old config.json without llmProviders keeps default ''
    config.llmProviders = json['llmProviders'] !== undefined && json['llmProviders'] !== null ? json['llmProviders'] as string : ''
    // P69: tolerant read — old config without updateSourcePref keeps default 'auto'
    const usp = json['updateSourcePref']
    config.updateSourcePref = usp === 'cn' || usp === 'global' ? usp as string : 'auto'
    return config
  }

  static getDefault(): AppConfig {
    return new AppConfig()
  }

  /**
   * bug-1 fix: 设备端 TextInput 受控回灌缺陷会把"旧值+新输入"无缝拼成
   * "http://Ahttp://B" 形态的污染 URL。清洗策略: 按 http(s):// 边界切分,
   * 取最后一段(用户最新输入意图), 保证落盘/生效的始终是单一 URL。
   */
  static sanitizeLlmBaseUrl(url: string): string {
    let v = url.trim()
    const parts = v.split(/(?=https?:\/\/)/)
    if (parts.length > 1) {
      v = parts[parts.length - 1].trim()
    }
    return v
  }

  validate(): string[] {
    const errors: string[] = []
    if (this.mcpPort < 1024 || this.mcpPort > 65535) {
      errors.push('mcpPort must be between 1024 and 65535')
    }
    if (this.wsPort < 1024 || this.wsPort > 65535) {
      errors.push('wsPort must be between 1024 and 65535')
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
    if (this.llmBaseUrl && !this.llmBaseUrl.startsWith('http://') && !this.llmBaseUrl.startsWith('https://')) {
      errors.push('llmBaseUrl must start with http:// or https://')
    }
    if (this.llmBaseUrl && this.llmBaseUrl.includes(' ')) {
      errors.push('llmBaseUrl must not contain spaces')
    }
    return errors
  }
}