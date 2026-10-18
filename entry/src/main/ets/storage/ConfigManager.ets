import { AppConfig, AppConfigUpdate } from '../model/AppConfig'
import { StorageManager } from './StorageManager'
import { SecureStorageAdapter } from './SecureStorageAdapter'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'

/** P36: asset 别名（真加密秘密的系统安全存储键） */
const ALIAS_LLM_KEY = 'llm_api_key'
const ALIAS_LLM_PROVIDERS_KEYS = 'llm_providers_keys'

interface LlmProviderRec {
  name: string
  baseUrl: string
  apiKey: string
  model: string
}

class ConfigManagerImpl {
  private config: AppConfig = AppConfig.getDefault()
  private configPath: string = 'config.json'
  private loaded: boolean = false

  async load(): Promise<AppConfig> {
    // P36: 先探 asset 服务（幂等；不可用时全链路走明文降级）
    await SecureStorageAdapter.init()
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
    await this.migratePlaintextKeys(json !== null)
    await this.restoreKeysFromAsset()
    this.loaded = true
    return this.config
  }

  /**
   * P36 一次性迁移：旧版 config.json 内的明文密钥（llmApiKey / llmProviders[].apiKey）
   * 搬入 asset 真加密存储，随后由 save() 落回脱敏 config.json（盘上不再有密钥明文）。
   * asset 不可用或写入失败 → 明文保留（降级，不丢用户数据）。
   */
  private async migratePlaintextKeys(hadFile: boolean): Promise<void> {
    if (!SecureStorageAdapter.isSecureStorageAvailable()) {
      if (this.config.llmApiKey.length > 0 || this.hasProviderKeyInMemory()) {
        console.warn('[P36] asset unavailable: plaintext keys retained in config.json (fallback)')
      }
      return
    }
    const legacyKey = this.config.llmApiKey
    let migrated = false
    if (legacyKey.length > 0) {
      const ok = await SecureStorageAdapter.putSecret(ALIAS_LLM_KEY, legacyKey)
      if (ok) {
        console.info('[P36] migrated llm_api_key to asset: ' + AppConfig.keyFingerprint(legacyKey))
        migrated = true
      } else {
        console.warn('[P36] llm_api_key migration FAILED — plaintext retained (fallback)')
      }
    }
    // providers 明文 keys → asset map
    if (this.hasProviderKeyInMemory()) {
      const map: Record<string, string> = this.extractProviderKeys()
      const keys = Object.keys(map)
      if (keys.length > 0) {
        const ok = await SecureStorageAdapter.putSecret(ALIAS_LLM_PROVIDERS_KEYS, JSON.stringify(map))
        if (ok) {
          console.info('[P36] migrated llm_providers_keys to asset: ' + keys.length + ' entries')
          migrated = true
        } else {
          console.warn('[P36] llm_providers_keys migration FAILED — plaintext retained (fallback)')
        }
      }
    }
    if (migrated && hadFile) {
      // 内存保留真值、盘上立即换成脱敏形态（save 内含 asset 同步 + 脱敏 toJSON 落盘）
      await this.save()
      console.info('[P36] config.json rewritten without plaintext keys')
    }
  }

  /** P36: 启动时从 asset 回灌内存真值（config.json 里只有脱敏空串） */
  private async restoreKeysFromAsset(): Promise<void> {
    if (!SecureStorageAdapter.isSecureStorageAvailable()) {
      return
    }
    const realKey = await SecureStorageAdapter.getSecret(ALIAS_LLM_KEY)
    if (realKey !== null && realKey.length > 0) {
      this.config.llmApiKey = realKey
      console.info('[P36] llm_api_key restored from asset: ' + AppConfig.keyFingerprint(realKey))
    }
    const providersKeysRaw = await SecureStorageAdapter.getSecret(ALIAS_LLM_PROVIDERS_KEYS)
    if (providersKeysRaw !== null && providersKeysRaw.length > 0 && this.config.llmProviders.length > 0) {
      try {
        const map = JSON.parse(providersKeysRaw) as Record<string, Object>
        const arr = JSON.parse(this.config.llmProviders) as LlmProviderRec[]
        if (Array.isArray(arr)) {
          let restored = 0
          for (const it of arr) {
            const v = map[it.name]
            if (v !== undefined && typeof v === 'string' && (v as string).length > 0) {
              it.apiKey = v as string
              restored++
            }
          }
          this.config.llmProviders = JSON.stringify(arr)
          if (restored > 0) {
            console.info('[P36] provider keys restored from asset: ' + restored)
          }
        }
      } catch (e) {
        console.warn('[P36] provider keys restore parse fail: ' + e)
      }
    }
  }

  async save(): Promise<boolean> {
    const errors = this.config.validate()
    if (errors.length > 0) {
      ErrorHandler.handle(new AppError(ErrorCodes.CFG_001, errors.join('; ')))
      return false
    }
    await this.syncKeysToAsset()
    // P36: asset 可用 → 脱敏落盘（密钥在 asset）；降级 → 明文落盘（保留旧行为，不丢数据）
    const secureMode = SecureStorageAdapter.isSecureStorageAvailable()
    const payload = secureMode ? this.config.toJSON() : this.config.toJSONPlain()
    const result = await StorageManager.saveJSON(this.configPath, payload)
    if (result) {
      EventBus.emit(EventBusEvents.CONFIG_CHANGE, payload)
    }
    return result
  }

  /**
   * P36: save 前把真值密钥同步进 asset。
   * - asset 可用：llmApiKey / providers keys 全量写入（空则移除）
   * - asset 不可用：跳过（toJSON 保留原字段值？否——toJSON 恒脱敏，
   *   降级模式下明文保留靠 load 时不迁移 + save 时此处兜底直接明文落盘）
   */
  private async syncKeysToAsset(): Promise<void> {
    if (!SecureStorageAdapter.isSecureStorageAvailable()) {
      // 降级：明文照旧走 config.json。toJSON 会脱敏导致明文丢失 ——
      // 故降级模式下直接写明文版 JSON（绕过 toJSON 脱敏出口）。
      if (this.config.llmApiKey.length > 0 || this.hasProviderKeyInMemory()) {
        console.warn('[P36] save in fallback mode: plaintext keys stay in config.json')
      }
      return
    }
    if (this.config.llmApiKey.length > 0) {
      const ok = await SecureStorageAdapter.putSecret(ALIAS_LLM_KEY, this.config.llmApiKey)
      if (ok) {
        console.info('[P36] llm_api_key -> asset: ' + AppConfig.keyFingerprint(this.config.llmApiKey))
      } else {
        console.warn('[P36] llm_api_key asset save FAILED')
      }
    } else {
      await SecureStorageAdapter.removeSecret(ALIAS_LLM_KEY)
    }
    const map: Record<string, string> = this.extractProviderKeys()
    const keys = Object.keys(map)
    if (keys.length > 0) {
      const ok = await SecureStorageAdapter.putSecret(ALIAS_LLM_PROVIDERS_KEYS, JSON.stringify(map))
      if (!ok) {
        console.warn('[P36] llm_providers_keys asset save FAILED')
      }
    } else {
      await SecureStorageAdapter.removeSecret(ALIAS_LLM_PROVIDERS_KEYS)
    }
  }

  /** P36: 内存 providers 里是否存在非空 apiKey */
  private hasProviderKeyInMemory(): boolean {
    if (this.config.llmProviders.length === 0) {
      return false
    }
    try {
      const arr = JSON.parse(this.config.llmProviders) as LlmProviderRec[]
      if (!Array.isArray(arr)) {
        return false
      }
      for (const it of arr) {
        if (it.apiKey && it.apiKey.length > 0) {
          return true
        }
      }
    } catch (e) {
    }
    return false
  }

  /** P36: 提取 providers name->apiKey 映射（只含非空 key） */
  private extractProviderKeys(): Record<string, string> {
    const map: Record<string, string> = {}
    if (this.config.llmProviders.length === 0) {
      return map
    }
    try {
      const arr = JSON.parse(this.config.llmProviders) as LlmProviderRec[]
      if (Array.isArray(arr)) {
        for (const it of arr) {
          if (it.apiKey && it.apiKey.length > 0) {
            map[it.name] = it.apiKey
          }
        }
      }
    } catch (e) {
    }
    return map
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
    if (config.darkMode !== undefined) {
      this.config.darkMode = config.darkMode
    }
    if (config.sensitiveConfirm !== undefined) {
      this.config.sensitiveConfirm = config.sensitiveConfirm
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
    if (config.searchEngineId !== undefined) {
      this.config.searchEngineId = config.searchEngineId
    }
    if (config.llmProviders !== undefined) {
      this.config.llmProviders = config.llmProviders
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

  isDarkMode(): boolean {
    return this.config.darkMode
  }

  getSearchEngineId(): string {
    return this.config.searchEngineId
  }

  isSensitiveConfirm(): boolean {
    return this.config.sensitiveConfirm
  }
}

export const ConfigManager = new ConfigManagerImpl()
