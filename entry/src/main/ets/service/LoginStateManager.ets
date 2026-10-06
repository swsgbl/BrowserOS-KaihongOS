import { LoginStateData, CookieEntry } from '../model/LoginStateData'
import { SecureStorageAdapter } from '../storage/SecureStorageAdapter'
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { webview } from '@kit.ArkWeb'

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
    const filePath = `login_state/${state.domain}.json`
    if (SecureStorageAdapter.isSecureStorageAvailable()) {
      return SecureStorageAdapter.encryptStoreJSON(filePath, state.toJSON())
    } else {
      return StorageManager.saveJSON(filePath, state.toJSON())
    }
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
    const files = await StorageManager.listDir('login_state')
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
        } catch (e) {
          console.error(`Failed to load login state for ${domain}: ${e}`)
        }
      }
    }
  }
}

export const LoginStateManager = new LoginStateManagerImpl()