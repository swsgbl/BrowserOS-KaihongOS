import { DocType } from '../enums/DocEnums'
import { DocConfig } from '../models/DocDataTypes'
import { DocStorageManager } from './DocStorageManager'
import { DocPathResolver } from './DocPathResolver'
import { EventBus } from '../../infra/EventBus'
import { ErrorHandler, AppError } from '../../infra/ErrorHandler'
import { DocErrorCodes } from '../common/DocErrorCodes'

export const DOC_CONFIG_EVENT: string = 'doc-config-changed'
const DOC_CONFIG_FILE: string = 'doc-config.json'

class DocConfigManagerImpl {
  private config: DocConfig = DocConfigManagerImpl.getDefault()

  static getDefault(): DocConfig {
    const defaultConfig: DocConfig = {
      archiveRetentionDays: 365,
      namingConvention: 'kebab-case',
      templateVersion: '1.0.0'
    }
    return defaultConfig
  }

  async loadConfig(): Promise<DocConfig> {
    try {
      const json = await DocStorageManager.load(DOC_CONFIG_FILE)
      if (json) {
        const parsed = JSON.parse(json)
        this.config = DocConfigManagerImpl.fromJSON(parsed)
      } else {
        this.config = DocConfigManagerImpl.getDefault()
        await this.saveConfig(this.config)
      }
      return this.config
    } catch (e) {
      this.config = DocConfigManagerImpl.getDefault()
      return this.config
    }
  }

  static fromJSON(obj: Object): DocConfig {
    const source = obj as Record<string, Object>
    const config: DocConfig = {
      archiveRetentionDays: typeof source['archiveRetentionDays'] === 'number' ? source['archiveRetentionDays'] as number : 365,
      namingConvention: typeof source['namingConvention'] === 'string' ? source['namingConvention'] as string : 'kebab-case',
      templateVersion: typeof source['templateVersion'] === 'string' ? source['templateVersion'] as string : '1.0.0'
    }
    return config
  }

  toJSON(config: DocConfig): Record<string, Object> {
    const result: Record<string, Object> = {
      'archiveRetentionDays': config.archiveRetentionDays,
      'namingConvention': config.namingConvention,
      'templateVersion': config.templateVersion
    }
    return result
  }

  validate(config: DocConfig): string[] {
    const errors: string[] = []
    if (config.archiveRetentionDays < 30) {
      errors.push('归档保留天数必须 >= 30')
    }
    if (!config.namingConvention || config.namingConvention.length === 0) {
      errors.push('命名规范不能为空')
    }
    const versionRegex = /^\d+\.\d+\.\d+$/
    if (!versionRegex.test(config.templateVersion)) {
      errors.push('模板版本号必须符合 MAJOR.MINOR.PATCH 格式')
    }
    return errors
  }

  async saveConfig(config: DocConfig): Promise<boolean> {
    const errors = this.validate(config)
    if (errors.length > 0) {
      ErrorHandler.handle(new AppError(DocErrorCodes.DOC_STG_001, errors.join('; ')))
      return false
    }
    this.config = config
    const result = await DocStorageManager.save(DOC_CONFIG_FILE, JSON.stringify(this.toJSON(config)))
    if (result) {
      EventBus.emit(DOC_CONFIG_EVENT, this.toJSON(config))
    }
    return result
  }

  getTemplatePath(type: DocType): string {
    return DocPathResolver.resolvePath(type)
  }

  get(): DocConfig {
    return this.config
  }
}

export const DocConfigManager = new DocConfigManagerImpl()