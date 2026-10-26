/**
 * P48: 轻量国际化框架（中/英切换 + Preferences 持久化）
 *
 * 设计（ArkTS 严格 / API≤23 兼容）：
 * - 语言包：I18nZh/I18nEn 导出 buildZhMap()/buildEnMap() → Map<string,string>。
 *   ArkTS 禁索引签名与索引访问（arkts-no-indexed-signatures/props-by-index），
 *   Map.get 是唯一合规的动态字符串查找。两包 key 一致由 tools/p48_check.cjs 校验。
 * - 存取：locale 存 'app_config' Preferences 的 'app_locale' key（与 ConfigManager 同 store）。
 *   I18n.init(context) 在 EntryAbility onCreate 调用（幂等），读完 saved locale 后写
 *   AppStorage('app_locale') —— 首帧 zh、读回 en 后触发一次重渲染。
 * - UI 刷新：页面声明 @StorageProp('app_locale') @Watch('onLocaleFlip')，
 *   onLocaleFlip 递增本地 @State（如 localeVersion）作为渲染依赖锚，
 *   build 内 I18n.t('key') 调用即可刷新（同 P26 darkMode 的 themeVersion 模式）。
 * - 回退：当前包缺 key 回退另一包，再回 key 本身（便于发现漏翻）。
 */
import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { buildZhMap } from './I18nZh'
import { buildEnMap } from './I18nEn'

class I18nImpl {
  private locale: string = 'zh'
  private zh: Map<string, string> = buildZhMap()
  private en: Map<string, string> = buildEnMap()
  private prefs: preferences.Preferences | null = null
  private initPromise: Promise<void> | null = null
  private context: Context | null = null

  /** EntryAbility onCreate 调用；幂等（并发复用同一 Promise） */
  init(context: Context): Promise<void> {
    this.context = context
    if (this.initPromise === null) {
      this.initPromise = this.doInit()
    }
    return this.initPromise
  }

  private async doInit(): Promise<void> {
    if (this.context === null) {
      return
    }
    try {
      this.prefs = await preferences.getPreferences(this.context, 'app_config')
    } catch (e) {
      console.error('[I18n] prefs init failed: ' + e)
      return
    }
    try {
      const v = await this.prefs.get('app_locale', 'zh')
      const saved = typeof v === 'string' ? v : 'zh'
      this.locale = saved === 'en' ? 'en' : 'zh'
    } catch (e) {
      console.error('[I18n] read locale failed: ' + e)
      this.locale = 'zh'
    }
    AppStorage.setOrCreate('app_locale', this.locale)
    console.info('[I18n] init done locale=' + this.locale)
  }

  private table(): Map<string, string> {
    return this.locale === 'en' ? this.en : this.zh
  }

  /** 取当前语言字符串；缺失回退另一语言包，再回 key 本身（空串是合法值——如 en 的 ntCountEnd） */
  t(key: string): string {
    const v = this.table().get(key)
    if (v !== undefined) {
      return v
    }
    const fb = this.locale === 'en' ? this.zh : this.en
    const fv = fb.get(key)
    if (fv !== undefined) {
      return fv
    }
    return key
  }

  /** 切换语言并持久化；写 AppStorage('app_locale') 触发各页 @Watch 刷新 */
  async setLocale(locale: string): Promise<void> {
    const target = locale === 'en' ? 'en' : 'zh'
    this.locale = target
    AppStorage.setOrCreate('app_locale', target)
    if (this.prefs === null && this.context !== null) {
      try {
        this.prefs = await preferences.getPreferences(this.context, 'app_config')
      } catch (e) {
        console.error('[I18n] prefs re-init failed: ' + e)
        return
      }
    }
    if (this.prefs !== null) {
      try {
        await this.prefs.put('app_locale', target)
        await this.prefs.flush()
        console.info('[I18n] locale persisted: ' + target)
      } catch (e) {
        console.error('[I18n] persist locale failed: ' + e)
      }
    }
  }

  getLocale(): string {
    return this.locale
  }

  /** 当前语言包条目数（诊断用） */
  getBundleSize(): number {
    return this.table().size
  }
}

export const I18n = new I18nImpl()
