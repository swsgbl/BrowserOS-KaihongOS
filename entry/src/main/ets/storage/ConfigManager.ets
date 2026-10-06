import { AppConfig, AppConfigUpdate } from '../model/AppConfig'
import { StorageManager } from './StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'

class ConfigManagerImpl {
  private config: AppConfig = AppConfig.getDefault()
  private configPath: string = 'config.json'

  async load(): Promise<AppConfig> {
    const json = await StorageManager.loadJSON(this.configPath)
    if (json) {
      try {
        this.config = AppConfig.fromJSON(json)
      } catch (e) {
        ErrorHandler.handle(new AppError(ErrorCodes.CFG_002, `Config load failed: ${e}`))
        this.config = AppConfig.getDefault()
      }
    } else {
      this.config = AppConfig.getDefault()
      await this.save()
    }
    return this.config
  }

  async save(): Promise<boolean> {
    const errors = this.config.validate()
    if (errors.length > 0) {
      ErrorHandler.handle(new AppError(ErrorCodes.CFG_001, errors.join('; ')))
      return false
    }
    const result = await StorageManager.saveJSON(this.configPath, this.config.toJSON())
    if (result) {
      EventBus.emit(EventBusEvents.CONFIG_CHANGE, this.config.toJSON())
    }
    return result
  }

  get(): AppConfig {
    return this.config
  }

  set(config: AppConfigUpdate): void {
    if (config.mcpPort !== undefined) {
      this.config.mcpPort = config.mcpPort
    }
    if (config.maxAgents !== undefined) {
      this.config.maxAgents = config.maxAgents
    }
    if (config.recordingQuality !== undefined) {
      this.config.recordingQuality = config.recordingQuality
    }
    if (config.recordingMaxSpaceMb !== undefined) {
      this.config.recordingMaxSpaceMb = config.recordingMaxSpaceMb
    }
    if (config.snapshotCompressionRatio !== undefined) {
      this.config.snapshotCompressionRatio = config.snapshotCompressionRatio
    }
    if (config.agentTimeoutMinutes !== undefined) {
      this.config.agentTimeoutMinutes = config.agentTimeoutMinutes
    }
    if (config.isOnboardingCompleted !== undefined) {
      this.config.isOnboardingCompleted = config.isOnboardingCompleted
    }
    if (config.isNeoMode !== undefined) {
      this.config.isNeoMode = config.isNeoMode
    }
    if (config.telemetryEnabled !== undefined) {
      this.config.telemetryEnabled = config.telemetryEnabled
    }
    if (config.llmBaseUrl !== undefined) {
      this.config.llmBaseUrl = AppConfig.sanitizeLlmBaseUrl(config.llmBaseUrl)
    }
    if (config.llmApiKey !== undefined) {
      this.config.llmApiKey = config.llmApiKey.trim()
    }
    if (config.llmModel !== undefined) {
      this.config.llmModel = config.llmModel.trim()
    }
  }

  async update(config: AppConfigUpdate): Promise<boolean> {
    this.set(config)
    return this.save()
  }

  getMcpPort(): number {
    return this.config.mcpPort
  }

  getMaxAgents(): number {
    return this.config.maxAgents
  }

  isOnboardingCompleted(): boolean {
    return this.config.isOnboardingCompleted
  }

  isNeoMode(): boolean {
    return this.config.isNeoMode
  }

  getLlmBaseUrl(): string {
    return this.config.llmBaseUrl
  }

  getLlmApiKey(): string {
    return this.config.llmApiKey
  }

  getLlmModel(): string {
    return this.config.llmModel
  }

  isLlmConfigured(): boolean {
    return this.config.llmBaseUrl.length > 0
  }
}

export const ConfigManager = new ConfigManagerImpl()