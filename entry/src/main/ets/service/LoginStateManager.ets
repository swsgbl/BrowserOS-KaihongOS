import { LoginStateData, CookieEntry } from '../model/LoginStateData'
import { SecureStorageAdapter } from '../storage/SecureStorageAdapter'
import { StorageManager } from '../storage/StorageManager'
import { PrefsStore } from '../storage/PrefsStore'
import { Context } from '@kit.AbilityKit'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { webview } from '@kit.ArkWeb'

interface LoginSessionAgg {
  domains: Record<string, Object>
}

interface LoginStateImportedData {
  domains: string[]
  count: number
}

interface CookieEntryJSONLike {
  name: string
  value: string
  domain: string
  path: string
  expires: number
}

class LoginStateManagerImpl {
  private importedDomains: Set<string> = new Set()
  private loginStates: Map<string, LoginStateData> = new Map()
  /**
   * P14b: 持久化载体迁 Preferences（login_state 实例，键 login_token/session_info_<domain>）。
   * Preferences 单 Value 上限 16MB —— token/会话 JSON 实际远小于该值；
   * 超限时 PrefsStore 降级截断并 hilog 警告。
   */
  private context: Context | null = null

  /** EntryAbility 启动调用（先于任何导入/装载） */
  init(context: Context): void {
    this.context = context
    PrefsStore.init(context).then(() => {
      console.info('[LoginStateManager] PrefsStore login_state ready')
    }).catch((e: Object) => {
      console.error('[LoginStateManager] PrefsStore init error: ' + e)
    })
  }

  async importFromChrome(): Promise<LoginStateData[]> {
    try {
      const chromeDataPath = this.detectChromeDataPath()
      if (!chromeDataPath) {
        ErrorHandler.handle(new AppError(ErrorCodes.LGN_001, 'Chrome not detected'))
        return []
      }

      const cookies = await this.readChromeCookies(chromeDataPath)
      const localStorage = await this.readChromeLocalStorage(chromeDataPath)

      const domainMap: Map<string, LoginStateData> = new Map()

      for (const cookie of cookies) {
        if (!domainMap.has(cookie.domain)) {
          domainMap.set(cookie.domain, new LoginStateData(cookie.domain))
        }
        domainMap.get(cookie.domain)!.addCookie(cookie)
      }

      localStorage.forEach((storage: Record<string, string>, domain: string) => {
        if (!domainMap.has(domain)) {
          domainMap.set(domain, new LoginStateData(domain))
        }
        const state = domainMap.get(domain)!
        const storageKeys = Object.keys(storage)
        for (const key of storageKeys) {
          state.setLocalStorageItem(key, storage[key])
        }
      })

      const results: LoginStateData[] = []
      const domainEntries = Array.from(domainMap.entries())
      for (const entry of domainEntries) {
        const domain = entry[0]
        const state = entry[1]
        state.isEncrypted = SecureStorageAdapter.isSecureStorageAvailable()
        await this.persistLoginState(state)
        this.importedDomains.add(domain)
        this.loginStates.set(domain, state)
        results.push(state)
      }

      await this.persistSessionInfo()
      const importedData: LoginStateImportedData = {
        domains: Array.from(this.importedDomains),
        count: results.length
      }
      EventBus.emit(EventBusEvents.LOGIN_STATE_IMPORTED, importedData)

      return results
    } catch (e) {
      ErrorHandler.handle(new AppError(ErrorCodes.LGN_002, `Chrome data format incompatible: ${e}`))
      return []
    }
  }

  async importSelected(domains: string[]): Promise<LoginStateData[]> {
    const allStates = await this.importFromChrome()
    return allStates.filter(state => domains.includes(state.domain))
  }

  /** P7: 从应用沙盒内 cookies.json 解析导入（格式: [{domain,name,value,path,expires?}]，容错） */
  parseCookieJson(jsonText: string): LoginStateData[] {
    const results: LoginStateData[] = []
    let parsed: Object
    try {
      parsed = JSON.parse(jsonText)
    } catch (e) {
      console.error('LoginStateManager parseCookieJson JSON.parse failed: ' + e)
      return results
    }
    let arr: Object[] = []
    if (Array.isArray(parsed)) {
      arr = parsed as Object[]
    } else {
      // 容错: { cookies: [...] } 或 { items: [...] } 包裹结构
      const obj = parsed as Record<string, Object>
      if (obj['cookies'] && Array.isArray(obj['cookies'])) {
        arr = obj['cookies'] as Object[]
      } else if (obj['items'] && Array.isArray(obj['items'])) {
        arr = obj['items'] as Object[]
      } else {
        console.error('LoginStateManager parseCookieJson: unrecognized structure')
        return results
      }
    }
    const byDomain: Map<string, LoginStateData> = new Map()
    let skipped: number = 0
    for (const item of arr) {
      const rec = item as Record<string, Object>
      const domain = (rec['domain'] as string || '').trim()
      const name = (rec['name'] as string || '').trim()
      const value = (rec['value'] as string || '')
      if (domain.length === 0 || name.length === 0) {
        skipped++
        continue
      }
      const entry = new CookieEntry(name, value, domain)
      entry.path = (rec['path'] as string || '/') || '/'
      const exp = rec['expires'] as number
      if (exp !== undefined && exp !== null) {
        entry.expires = exp
      }
      if (rec['secure'] !== undefined) {
        entry.secure = rec['secure'] as boolean
      }
      if (rec['httpOnly'] !== undefined) {
        entry.httpOnly = rec['httpOnly'] as boolean
      }
      if (!byDomain.has(domain)) {
        byDomain.set(domain, new LoginStateData(domain))
      }
      byDomain.get(domain)!.addCookie(entry)
    }
    byDomain.forEach((state: LoginStateData, domain: string) => {
      this.importedDomains.add(domain)
      this.loginStates.set(domain, state)
      results.push(state)
    })
    console.info('LoginStateManager parseCookieJson: cookies=' + arr.length +
      ' domains=' + results.length + ' skipped=' + skipped)
    return results
  }

  /** P7: 读取沙盒文件并 parse+持久化（供仪表盘「导入登录态」输入路径后调用） */
  async importFromCookieFile(relPath: string): Promise<LoginStateData[]> {
    try {
      const full = `${this.basePathForRead()}/${relPath}`
      const file = fs.openSync(full, fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(full)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      const text = util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer))
      const states = this.parseCookieJson(text)
      // 持久化 + 事件
      for (const state of states) {
        state.isEncrypted = SecureStorageAdapter.isSecureStorageAvailable()
        await this.persistLoginState(state)
      }
      await this.persistSessionInfo()
      const importedData: LoginStateImportedData = {
        domains: Array.from(this.importedDomains),
        count: states.length
      }
      EventBus.emit(EventBusEvents.LOGIN_STATE_IMPORTED, importedData)
      console.info('LoginStateManager importFromCookieFile: ' + relPath + ' -> ' + states.length + ' domains')
      return states
    } catch (e) {
      console.error('LoginStateManager importFromCookieFile error: ' + e)
      return []
    }
  }

  private basePathForRead(): string {
    // 复用 StorageManager 基路径（EntryAbility 已 setBasePath 为 filesDir）
    return StorageManager.getBasePath()
  }

  getImportedDomains(): string[] {
    return Array.from(this.importedDomains)
  }

  getLoginState(domain: string): LoginStateData | null {
    return this.loginStates.get(domain) || null
  }

  applyLoginState(domain: string): LoginStateData | null {
    return this.loginStates.get(domain) || null
  }

  async clearAll(): Promise<boolean> {
    this.importedDomains.clear()
    this.loginStates.clear()

    // P14b: Preferences 载体一并清空（login_token + session_info）
    await PrefsStore.clear('login_state')
    const files = await StorageManager.listDir('login_state')
    for (const file of files) {
      await StorageManager.delete(`login_state/${file}`)
    }
    return true
  }

  isSecureStorageAvailable(): boolean {
    return SecureStorageAdapter.isSecureStorageAvailable()
  }

  private detectChromeDataPath(): string | null {
    return null
  }

  private async readChromeCookies(chromeDataPath: string): Promise<CookieEntry[]> {
    return []
  }

  private async readChromeLocalStorage(chromeDataPath: string): Promise<Map<string, Record<string, string>>> {
    return new Map()
  }

  private async persistLoginState(state: LoginStateData): Promise<boolean> {
    // P14b: 首选 Preferences 载体（键 session_info_<domain>，JSON string）
    const jsonStr = JSON.stringify(state.toJSON())
    const prefsKey = 'session_info_' + state.domain
    const ok = await PrefsStore.putString('login_state', prefsKey, jsonStr)
    if (!ok) {
      console.warn('[LoginStateManager] prefs persist failed, fallback to legacy file: ' + state.domain)
    }
    // 兼容链: 加密可用时同步落一份加密 JSON 文件（旧读取方/导出仍可用）
    const filePath = `login_state/${state.domain}.json`
    if (SecureStorageAdapter.isSecureStorageAvailable()) {
      await SecureStorageAdapter.encryptStoreJSON(filePath, state.toJSON())
    } else {
      await StorageManager.saveJSON(filePath, state.toJSON())
    }
    return ok
  }

  /** P7: 把已导入的 cookies 逐条注入 WebView（webview 级，全局 cookie 配置） */
  async injectCookiesToWebview(): Promise<number> {
    let written: number = 0
    this.loginStates.forEach((state: LoginStateData, domain: string) => {
      for (const cookie of state.cookies) {
        try {
          // WebCookieManager.setCookie(url, cookie) — cookie 字符串形态
          const cookieStr = this.buildCookieString(cookie, domain)
          webview.WebCookieManager.configCookieSync('https://' + domain, cookieStr, false)
          written++
        } catch (e) {
          console.error('LoginStateManager setCookie failed: ' + e)
        }
      }
    })
    console.info('LoginStateManager injectCookiesToWebview: written=' + written)
    return written
  }

  private buildCookieString(cookie: CookieEntry, domain: string): string {
    let s = cookie.name + '=' + cookie.value
    s += '; Domain=' + domain
    if (cookie.path) {
      s += '; Path=' + cookie.path
    }
    if (cookie.expires > 0) {
      s += '; Expires=' + new Date(cookie.expires).toUTCString()
    }
    if (cookie.secure) {
      s += '; Secure'
    }
    if (cookie.httpOnly) {
      s += '; HttpOnly'
    }
    return s
  }

  /** P7: 导出当前已导入 cookies 为 JSON（便于测试/回读） */
  async exportCookiesJson(): Promise<string> {
    const all: CookieEntryJSONLike[] = []
    this.loginStates.forEach((state: LoginStateData) => {
      for (const c of state.cookies) {
        all.push({ name: c.name, value: c.value, domain: state.domain, path: c.path, expires: c.expires })
      }
    })
    return JSON.stringify(all)
  }

  async loadPersistedStates(): Promise<void> {
    // P14b: ensure prefs ready（幂等 init —— 修复启动竞态: 此前不等 init 完成即读, 每次误走 legacy 分支）
    if (this.context) {
      await PrefsStore.init(this.context)
    }
    // P14b: 首选 Preferences（login_token + session_info_<domain>）
    const token = await PrefsStore.getString('login_state', 'login_token', '')
    const sessionRaw = await PrefsStore.getString('login_state', 'session_info', '')
    if (sessionRaw.length > 0) {
      // 会话信息聚合形态: { domains: { <domain>: <LoginStateDataJSON> } }
      try {
        const agg = JSON.parse(sessionRaw) as Record<string, Object>
        const domains = agg['domains'] as Record<string, Object>
        if (domains) {
          for (const domain of Object.keys(domains)) {
            const state = LoginStateData.fromJSON(domains[domain] as Record<string, Object>)
            this.loginStates.set(domain, state)
            this.importedDomains.add(domain)
          }
          console.info('[LoginStateManager] loaded from Preferences: domains=' + Object.keys(domains).length + ' token=' + (token.length > 0 ? 'yes' : 'no'))
          return
        }
      } catch (e) {
        console.error('[LoginStateManager] session_info parse failed, fallback to legacy files: ' + e)
      }
    }
    // 旧载体一次性迁移: login_state/*.json -> Preferences 聚合键
    const files = await StorageManager.listDir('login_state')
      .then((raw: string[]) => raw.filter((f: string) => f.endsWith('.json') && !f.endsWith('.migrated')))
    let migrated = 0
    const aggDomains: Record<string, Object> = {}
    for (const file of files) {
      const domain = file.replace('.json', '')
      let json: Record<string, Object> | null = null
      if (SecureStorageAdapter.isSecureStorageAvailable()) {
        json = await SecureStorageAdapter.decryptLoadJSON(`login_state/${file}`)
      } else {
        json = await StorageManager.loadJSON(`login_state/${file}`)
      }
      if (json) {
        try {
          const state = LoginStateData.fromJSON(json)
          this.loginStates.set(domain, state)
          this.importedDomains.add(domain)
          aggDomains[domain] = state.toJSON()
          migrated++
          // 迁移完成后旧文件改名 .migrated（留档不删除）
          const raw = await StorageManager.load(`login_state/${file}`)
          if (raw !== null) {
            await StorageManager.save(`login_state/${file}.migrated`, raw)
            await StorageManager.delete(`login_state/${file}`)
          }
        } catch (e) {
          console.error(`Failed to load login state for ${domain}: ${e}`)
        }
      }
    }
    if (migrated > 0) {
      const agg: LoginSessionAgg = { domains: aggDomains }
      await PrefsStore.putString('login_state', 'session_info', JSON.stringify(agg))
      console.info('[LoginStateManager] legacy login_state migrated to Preferences: ' + migrated + ' domains')
    }
  }

  /** P14b: 聚合持久化（导入完成后调用）——把内存全部 state 写入 session_info 聚合键 */
  async persistSessionInfo(): Promise<void> {
    const aggDomains: Record<string, Object> = {}
    this.loginStates.forEach((state: LoginStateData, domain: string) => {
      aggDomains[domain] = state.toJSON()
    })
    const agg: LoginSessionAgg = { domains: aggDomains }
    await PrefsStore.putString('login_state', 'session_info', JSON.stringify(agg))
  }

  /** P14b: token 存取（Preferences login_token 键） */
  async saveLoginToken(token: string): Promise<boolean> {
    return PrefsStore.putString('login_state', 'login_token', token)
  }

  async getLoginToken(): Promise<string> {
    return PrefsStore.getString('login_state', 'login_token', '')
  }
}

export const LoginStateManager = new LoginStateManagerImpl()