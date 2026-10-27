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

// P53: 向导页统一从 service 导入（re-export）
export { LoginStateData, CookieEntry }

/** P53 导入来源类型 */
export enum ImportSourceKind {
  NETSCAPE = 'netscape',
  CHROME_JSON = 'chrome_json',
  BITWARDEN = 'bitwarden',
  MANUAL = 'manual'
}

/** P53 预览行（向导 Step3 展示单元） */
export class ImportPreviewRow {
  domain: string = ''
  cookieCount: number = 0
  nearestExpiry: number = 0   // 0 = 会话 cookie（不过期）
  expiredCount: number = 0
  duplicate: boolean = false  // 已存在于当前导入域集合
}

/** P53 单域导入结果 */
export class ImportDomainResult {
  domain: string = ''
  imported: number = 0
  skipped: number = 0
  failed: number = 0
  reasons: string[] = []
}

/** P53 导入执行汇总 */
export class ImportSummary {
  states: LoginStateData[] = []
  results: ImportDomainResult[] = []
  totalImported: number = 0
  totalSkipped: number = 0
  totalFailed: number = 0
}

/** P53 无痕 profile 常量 */
export const PROFILE_INCOGNITO: string = 'incognito'
export const PROFILE_DEFAULT: string = 'default'

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
    // P53: KaihongOS 沙盒不可直读其他应用 profile —— 不再探测，返回 null
    // 并由调用方（导入向导）引导用户走「文件导出 + 手动导入」路径
    return null
  }

  /** P53: 沙盒 filesDir 相对路径直读（adb 预置文件后的可靠导入通道） */
  /** P53: 扫描沙盒 filesDir 下可导入文件（.txt/.json，忽略隐藏项） */
  listSandboxImportable(): string[] {
    const out: string[] = []
    try {
      const ctx = this.context
      if (!ctx) {
        return out
      }
      const names = fs.listFileSync(ctx.filesDir)
      for (const n of names) {
        if (n.startsWith('.')) {
          continue
        }
        if (n.endsWith('.txt') || n.endsWith('.json')) {
          out.push(n)
        }
      }
    } catch (e) {
      console.error('[P53] listSandboxImportable failed: ' + e)
    }
    return out
  }

  readSandboxText(relPath: string): string {
    try {
      const ctx = this.context
      if (!ctx) {
        console.error('LoginStateManager readSandboxText: no context')
        return ''
      }
      const cleaned = relPath.replace(/^files\//, '')
      const full = ctx.filesDir + '/' + cleaned
      console.info('[P53] readSandboxText: full=' + full)
      return this.readTextFromUri(full)
    } catch (e) {
      console.error('LoginStateManager readSandboxText failed: ' + e)
      return ''
    }
  }

  /** P53: 从文件 URI 读取文本（DocumentViewPicker 返回的 uri 直接可 open） */
  readTextFromUri(fileUri: string): string {
    let file: fs.File | null = null
    try {
      file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(file.fd)
      if (stat.size > 8 * 1024 * 1024) {
        console.warn('LoginStateManager readTextFromUri: file too large ' + stat.size)
      }
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      file = null
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer))
    } catch (e) {
      if (file !== null) {
        try {
          fs.closeSync(file)
        } catch (err) {
        }
      }
      console.error('LoginStateManager readTextFromUri failed: ' + e)
      return ''
    }
  }

  /**
   * P53: Netscape cookie.txt 解析。
   * 行格式: domain \t flag \t path \t secure \t expiry \t name \t value
   * - '#' 开头为注释（识别 "# Netscape HTTP Cookie File" 头）
   * - expiry 为秒级 Unix；0/空 = 会话 cookie
   */
  parseNetscapeCookies(text: string): CookieEntry[] {
    const cookies: CookieEntry[] = []
    const lines = text.split(/\r?\n/)
    for (const rawLine of lines) {
      const line = rawLine.trim()
      if (line.length === 0 || line.startsWith('#')) {
        continue
      }
      const parts = line.split('\t')
      if (parts.length < 7) {
        // 容错：7 字段以空格分隔的变体（极少见）—— 不足 7 字段跳过
        continue
      }
      const domain = parts[0].trim()
      const name = parts[5].trim()
      if (domain.length === 0 || name.length === 0) {
        continue
      }
      const entry = new CookieEntry(name, parts[6], domain)
      entry.path = parts[2].trim().length > 0 ? parts[2].trim() : '/'
      entry.secure = parts[3].trim() === 'TRUE'
      const expRaw = parseInt(parts[4].trim())
      entry.expires = isNaN(expRaw) ? 0 : expRaw
      cookies.push(entry)
    }
    console.info('LoginStateManager parseNetscapeCookies: lines=' + lines.length + ' cookies=' + cookies.length)
    return cookies
  }

  /** P53: 自动识别导入格式（Netscape / Chrome JSON / Bitwarden） */
  detectFormat(text: string): ImportSourceKind {
    const head = text.substring(0, 512)
    if (head.indexOf('# Netscape HTTP Cookie File') >= 0 || head.indexOf('# Netscape') >= 0) {
      return ImportSourceKind.NETSCAPE
    }
    const trimmed = text.trimLeft()
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        const parsed = JSON.parse(text) as Record<string, Object>
        if (parsed['encrypted'] !== undefined || (parsed['items'] !== undefined && Array.isArray(parsed['items']))) {
          return ImportSourceKind.BITWARDEN
        }
        if (parsed['cookies'] !== undefined && Array.isArray(parsed['cookies'])) {
          return ImportSourceKind.CHROME_JSON
        }
      } catch (e) {
        // JSON 解析失败 → 当作无法识别
      }
      if (trimmed.startsWith('[')) {
        return ImportSourceKind.CHROME_JSON
      }
    }
    return ImportSourceKind.MANUAL
  }

  /** P53: 通用解析入口 —— 按格式分发，返回域聚合后的 states（未持久化） */
  parseAny(text: string, kindHint: ImportSourceKind): LoginStateData[] {
    const kind = kindHint === ImportSourceKind.MANUAL ? this.detectFormat(text) : kindHint
    const byDomain: Map<string, LoginStateData> = new Map()
    if (kind === ImportSourceKind.NETSCAPE) {
      for (const cookie of this.parseNetscapeCookies(text)) {
        if (!byDomain.has(cookie.domain)) {
          byDomain.set(cookie.domain, new LoginStateData(cookie.domain))
        }
        byDomain.get(cookie.domain)!.addCookie(cookie)
      }
    } else if (kind === ImportSourceKind.CHROME_JSON) {
      return this.parseCookieJson(text)
    } else if (kind === ImportSourceKind.BITWARDEN) {
      // Bitwarden JSON: {items:[{login:{uris:[{uri}],username,password}}]}
      try {
        const parsed = JSON.parse(text) as Record<string, Object>
        const items = parsed['items'] as Record<string, Object>[]
        if (items) {
          for (const item of items) {
            const login = item['login'] as Record<string, Object>
            if (!login) {
              continue
            }
            const uris = login['uris'] as Record<string, Object>[]
            if (!uris || uris.length === 0) {
              continue
            }
            const uri = (uris[0]['uri'] as string) || ''
            const host = this.hostOf(uri)
            if (host.length === 0) {
              continue
            }
            if (!byDomain.has(host)) {
              byDomain.set(host, new LoginStateData(host))
            }
            // Bitwarden 凭据以 localStorage 伪键承载（P47-B CredentialStore 为主载体）
            const state = byDomain.get(host)!
            const uname = (login['username'] as string) || ''
            const pwd = (login['password'] as string) || ''
            state.setLocalStorageItem('__bw_username', uname)
            state.setLocalStorageItem('__bw_password', pwd)
          }
        }
      } catch (e) {
        console.error('LoginStateManager parseAny bitwarden failed: ' + e)
      }
    }
    const states: LoginStateData[] = []
    byDomain.forEach((state: LoginStateData) => {
      states.push(state)
    })
    return states
  }

  /** P53: 从 uri 提取 host（scheme://host[:port]/path） */
  hostOf(uri: string): string {
    try {
      const m = uri.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/?:#]+)/)
      return m ? m[1] : ''
    } catch (e) {
      return ''
    }
  }

  /** P53: 生成预览行（域名排序、最近过期、重复标记） */
  buildPreview(states: LoginStateData[]): ImportPreviewRow[] {
    const rows: ImportPreviewRow[] = []
    const sorted = states.slice().sort((a: LoginStateData, b: LoginStateData): number => a.domain.localeCompare(b.domain))
    const now = Date.now() / 1000
    for (const state of sorted) {
      const row = new ImportPreviewRow()
      row.domain = state.domain
      row.cookieCount = state.cookies.length
      row.duplicate = this.loginStates.has(state.domain)
      let nearest = 0
      let expired = 0
      for (const c of state.cookies) {
        if (c.expires > 0) {
          if (nearest === 0 || c.expires < nearest) {
            nearest = c.expires
          }
          if (c.expires < now) {
            expired++
          }
        }
      }
      row.nearestExpiry = nearest
      row.expiredCount = expired
      rows.push(row)
    }
    return rows
  }

  /**
   * P53: 执行导入（向导 Step4）—— 持久化 + 注入 WebView + 事件。
   * 仅导入勾选域名；逐域统计成功/跳过（重复域全跳）/失败。
   */
  async executeImport(states: LoginStateData[], selectedDomains: string[]): Promise<ImportSummary> {
    const summary = new ImportSummary()
    const now = Date.now() / 1000
    const sel = new Set<string>()
    for (const d of selectedDomains) {
      sel.add(d)
    }
    for (const state of states) {
      const res = new ImportDomainResult()
      res.domain = state.domain
      if (!sel.has(state.domain)) {
        res.skipped = state.cookies.length
        res.reasons.push('unselected')
        summary.totalSkipped += res.skipped
        summary.results.push(res)
        continue
      }
      // 过期 cookie 跳过（不入库）
      const fresh: CookieEntry[] = []
      let expiredSkipped = 0
      for (const c of state.cookies) {
        if (c.expires > 0 && c.expires < now) {
          expiredSkipped++
        } else {
          fresh.push(c)
        }
      }
      if (expiredSkipped > 0) {
        res.skipped = expiredSkipped
        res.reasons.push(`expired cookies: ${expiredSkipped}`)
        summary.totalSkipped += expiredSkipped
      }
      if (fresh.length === 0 && expiredSkipped > 0) {
        res.reasons.push('all cookies expired — domain skipped')
        summary.results.push(res)
        continue
      }
      const target = new LoginStateData(state.domain)
      for (const c of fresh) {
        target.addCookie(c)
      }
      target.localStorage = state.localStorage
      target.sessionStorage = state.sessionStorage
      target.isEncrypted = SecureStorageAdapter.isSecureStorageAvailable()
      try {
        await this.persistLoginState(target)
        this.importedDomains.add(state.domain)
        this.loginStates.set(state.domain, target)
        res.imported = fresh.length
        summary.totalImported += fresh.length
        summary.states.push(target)
      } catch (e) {
        res.failed = fresh.length
        res.reasons.push(`persist failed: ${e}`)
        summary.totalFailed += fresh.length
      }
      summary.results.push(res)
    }
    if (summary.states.length > 0) {
      await this.persistSessionInfo()
      const importedData: LoginStateImportedData = {
        domains: summary.states.map((s: LoginStateData): string => s.domain),
        count: summary.states.length
      }
      EventBus.emit(EventBusEvents.LOGIN_STATE_IMPORTED, importedData)
      // P53: 导入即注入（configCookieSync 全局 cookie 管理器）
      const written = await this.injectCookiesToWebview()
      console.info(`[P53] executeImport: imported=${summary.totalImported} skipped=${summary.totalSkipped} failed=${summary.totalFailed} injected=${written}`)
    }
    return summary
  }

  /** P53: 对单个域名注入 cookies（供导航到对应域时按需调用） */
  async injectDomainCookies(domain: string): Promise<number> {
    const state = this.loginStates.get(domain)
    if (!state) {
      return 0
    }
    let written = 0
    for (const cookie of state.cookies) {
      try {
        const cookieStr = this.buildCookieString(cookie, domain)
        webview.WebCookieManager.configCookieSync('https://' + domain, cookieStr, false)
        written++
      } catch (e) {
        console.error('[P53] injectDomainCookies setCookie failed: ' + e)
      }
    }
    console.info(`[P53] injectDomainCookies domain=${domain} written=${written}`)
    return written
  }

  /** P53: 读取全局 CookieManager 中的域 cookie（验证注入效果/无痕不残留） */
  fetchCookieForVerify(domain: string, incognito: boolean = false): string {
    try {
      return webview.WebCookieManager.fetchCookieSync('https://' + domain, incognito)
    } catch (e) {
      console.warn('[P53] fetchCookieForVerify failed: ' + e)
      return ''
    }
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
    // P36: asset 真加密可用时不再落文件副本（Preferences 载体已唯一真源；
    // 旧 XOR 伪加密文件通道关闭）。asset 不可用的降级环境保留明文文件兜底。
    if (SecureStorageAdapter.isSecureStorageAvailable()) {
      return ok
    }
    const filePath = `login_state/${state.domain}.json`
    await StorageManager.saveJSON(filePath, state.toJSON())
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
    // 含 .migrated 档案回灌: prefs 为空且档案在盘时自愈（修复早期竞态期 putString 静默失败导致的数据未落）
    const MIGRATED_SUFFIX = '.migrated'
    // 任意 .json 谱系文件均纳入（.json / .json.migrated / 重复改名产生的 .json.migrated.migrated 等）
    const files = await StorageManager.listDir('login_state')
      .then((raw: string[]) => raw.filter((f: string) => f.includes('.json')))
    let migrated = 0
    const aggDomains: Record<string, Object> = {}
    for (const file of files) {
      const isArchive = file.indexOf('.json') !== file.length - '.json'.length
      const domain = file.substring(0, file.indexOf('.json'))
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
          // 迁移完成后旧文件改名 .migrated（留档不删除; 档案文件本身不再重复改名）
          if (!isArchive) {
            const raw = await StorageManager.load(`login_state/${file}`)
            if (raw !== null) {
              await StorageManager.save(`login_state/${file}.migrated`, raw)
              await StorageManager.delete(`login_state/${file}`)
            }
          }
        } catch (e) {
          console.error(`Failed to load login state for ${domain}: ${e}`)
        }
      }
    }
    if (migrated > 0) {
      const agg: LoginSessionAgg = { domains: aggDomains }
      await PrefsStore.putString('login_state', 'session_info', JSON.stringify(agg))
      console.info('[LoginStateManager] legacy login_state migrated to Preferences: ' + migrated + ' domains (P36: legacy decrypt path retained read-only)')
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