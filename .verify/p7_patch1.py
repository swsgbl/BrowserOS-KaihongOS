"""
P7-1: cookies.json import + WebView cookie injection.
Adds parseCookieJson + injectCookiesToWebview to LoginStateManager,
and changes Dashboard's import-login button to a real path-based import flow.
"""
import io, os, sys, re

ROOT = r'D:\BrowserOS - KaihongOS'

def patch(path, old, new, label):
    full = os.path.join(ROOT, path)
    with io.open(full, 'r', encoding='utf-8') as f:
        src = f.read()
    # Normalize: file may be CRLF or LF
    if old not in src:
        old2 = old.replace('\n', '\r\n')
        new2 = new.replace('\n', '\r\n')
        if old2 in src:
            old, new = old2, new2
        else:
            raise SystemExit('PATCH FAIL [%s]: old block not found\n--- old block ---\n%s' % (label, old[:400]))
    if src.count(old) != 1:
        raise SystemExit('PATCH FAIL [%s]: old block appears %d times' % (label, src.count(old)))
    src = src.replace(old, new, 1)
    with io.open(full, 'w', encoding='utf-8', newline='') as f:
        f.write(src)
    print('PATCH OK [%s]' % label)

# -----------------------------------------------------------------
# 1) LoginStateManager.ets — add parseCookieJson + injectCookiesToWebview
# -----------------------------------------------------------------
LS = 'entry/src/main/ets/service/LoginStateManager.ets'

# 1a. Add imports: webview (WebCookieManager) + fileIo for reading cookies file
old_imports = """import { LoginStateData, CookieEntry } from '../model/LoginStateData'
import { SecureStorageAdapter } from '../storage/SecureStorageAdapter'
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'"""

new_imports = """import { LoginStateData, CookieEntry } from '../model/LoginStateData'
import { SecureStorageAdapter } from '../storage/SecureStorageAdapter'
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { fileIo as fs } from '@kit.CoreFileKit'
import { webview } from '@kit.ArkWeb'"""
patch(LS, old_imports, new_imports, 'ls-imports')

# 1b. Add parseCookieJson method (tolerant JSON parse) before the trailing close of impl class.
#     Place it just before `getImportedDomains`
old_anchor = """  getImportedDomains(): string[] {
    return Array.from(this.importedDomains)
  }"""
new_block = """  /** P7: 从应用沙盒内 cookies.json 解析导入（格式: [{domain,name,value,path,expires?}]，容错） */
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
      const { util } = await import('@kit.ArkTS')
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
  }"""
patch(LS, old_anchor, new_block, 'ls-parseCookieJson')

# 1c. Add injectCookiesToWebview using webview.WebCookieManager (API<=14).
old_end = """  async loadPersistedStates(): Promise<void> {"""
new_end = """  /** P7: 把已导入的 cookies 逐条注入 WebView（webview 级，全局 cookie 配置） */
  async injectCookiesToWebview(): Promise<number> {
    let written: number = 0
    this.loginStates.forEach((state: LoginStateData, domain: string) => {
      for (const cookie of state.cookies) {
        try {
          // WebCookieManager.setCookie(url, cookie) — cookie 字符串形态
          const cookieStr = this.buildCookieString(cookie, domain)
          webview.WebCookieManager.setCookie('https://' + domain, cookieStr)
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

  async loadPersistedStates(): Promise<void> {"""
patch(LS, old_end, new_end, 'ls-inject')

# 1d. Add the supporting interface CookieEntryJSONLike near the top of the file
old_iface = "interface LoginStateImportedData {\n  domains: string[]\n  count: number\n}"
new_iface = old_iface + """

interface CookieEntryJSONLike {
  name: string
  value: string
  domain: string
  path: string
  expires: number
}"""
patch(LS, old_iface, new_iface, 'ls-iface')

# -----------------------------------------------------------------
# 2) BrowserShell.ets — replace the "功能开发中" AlertDialog with real import flow
# -----------------------------------------------------------------
BS = 'entry/src/main/ets/pages/BrowserShell.ets'

old_btn = """        Button('导入登录态')
          .fontSize(14)
          .backgroundColor('#9E6A03')
          .fontColor('#FFFFFF')
          .margin({ left: 12 })
          .onClick(() => {
            AlertDialog.show({
              title: '导入登录态',
              message: 'KaihongOS 无 Chrome 浏览器数据可导入。请使用外部导出的 cookies.json（功能开发中）。',
              primaryButton: { value: '知道了', action: () => { console.info('BrowserShell import-login acknowledged') } },
              cancel: () => { console.info('BrowserShell import-login dismissed') }
            })
          })"""

new_btn = """        Button('导入登录态')
          .fontSize(14)
          .backgroundColor('#9E6A03')
          .fontColor('#FFFFFF')
          .margin({ left: 12 })
          .onClick(() => {
            this.importLoginState()
          })"""
patch(BS, old_btn, new_btn, 'bs-btn')

# Add importLoginState method + state after toggleBookmark
old_method = """  /** P5: 历史面板（HistoryManager 接线） */
  private openHistory(): void {"""
new_method = """  /** P7: 导入登录态 —— 输入应用沙盒内 cookies.json 相对路径 → parse → WebCookieManager 注入 */
  @State showImportPanel: boolean = false
  @State importPath: string = ''
  @State importResult: string = ''

  private importLoginState(): void {
    this.importPath = ''
    this.importResult = ''
    this.showImportPanel = true
  }

  private doImport(): void {
    const path = this.importPath.trim()
    if (path.length === 0) {
      this.importResult = '请输入 cookies.json 的沙盒相对路径'
      return
    }
    LoginStateManager.importFromCookieFile(path).then((states) => {
      const n = states.length
      const written = 0
      if (n > 0) {
        // 注入 WebView cookies
        LoginStateManager.injectCookiesToWebview().then((count) => {
          this.importResult = `已导入 ${n} 个域 / 注入 ${count} 条 cookie`
          console.info('BrowserShell import-login: domains=' + n + ' injected=' + count)
        })
      } else {
        this.importResult = '未解析到 cookie（文件不存在或格式不符）'
        console.info('BrowserShell import-login: 0 domains parsed from ' + path)
      }
      this.showImportPanel = false
      // 回显到仪表盘
      this.showDashboard = true
    })
  }

  /** P7: 导入面板 Builder（挂在 Dashboard 内） */
  @Builder
  ImportLoginPanel(): void {
    Column() {
      Text('导入登录态 (cookies.json)')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E6EDF3')
      Text('输入应用沙盒 files/ 下的相对路径，如 files/cookies.json')
        .fontSize(12)
        .fontColor('#8B949E')
        .margin({ top: 8 })
      TextInput({ text: this.importPath, placeholder: 'files/cookies.json' })
        .width('100%')
        .height(40)
        .margin({ top: 12 })
        .onChange((v: string) => { this.importPath = v })
      if (this.importResult.length > 0) {
        Text(this.importResult)
          .fontSize(12)
          .fontColor('#4CAF50')
          .margin({ top: 8 })
      }
      Row() {
        Button('取消')
          .fontSize(14)
          .width(80)
          .height(36)
          .backgroundColor('#30363D')
          .fontColor('#E6EDF3')
          .onClick(() => { this.showImportPanel = false })
        Button('导入')
          .fontSize(14)
          .width(80)
          .height(36)
          .backgroundColor('#9E6A03')
          .fontColor('#FFFFFF')
          .margin({ left: 12 })
          .onClick(() => { this.doImport() })
      }
      .margin({ top: 12 })
    }
    .width('80%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor('#161B22')
  }

  /** P5: 历史面板（HistoryManager 接线） */
  private openHistory(): void {"""
patch(BS, old_method, new_method, 'bs-method')

# 2b. Wire importResult display into DashboardContent (replace the "导入登录态" hint area)
#     The importResult was showing under the dashboard buttons; add a small Text after the count line
old_count = """      Text('书签 ' + BookmarkManager.getBookmarkCount() + ' 条 · 历史 ' + HistoryManager.getAllHistory(500).length + ' 条')
        .fontSize(12)
        .fontColor('#8B949E')
        .margin({ top: 16 })"""
new_count = """      Text('书签 ' + BookmarkManager.getBookmarkCount() + ' 条 · 历史 ' + HistoryManager.getAllHistory(500).length + ' 条')
        .fontSize(12)
        .fontColor('#8B949E')
        .margin({ top: 16 })

      if (this.showImportPanel) {
        this.ImportLoginPanel()
      }
      if (this.importResult.length > 0 && !this.showImportPanel) {
        Text(this.importResult)
          .fontSize(12)
          .fontColor('#4CAF50')
          .margin({ top: 8 })
      }"""
patch(BS, old_count, new_count, 'bs-count')

# 2c. Add LoginStateManager import to BrowserShell
old_bs_imports = """import { ConfirmDialog } from '../components/ConfirmDialog'
import { NeoDashboardPanel } from '../components/NeoDashboardPanel'
import { webview } from '@kit.ArkWeb'
import { router } from '@kit.ArkUI'"""
new_bs_imports = """import { ConfirmDialog } from '../components/ConfirmDialog'
import { NeoDashboardPanel } from '../components/NeoDashboardPanel'
import { webview } from '@kit.ArkWeb'
import { router } from '@kit.ArkUI'
import { LoginStateManager } from '../service/LoginStateManager'"""
patch(BS, old_bs_imports, new_bs_imports, 'bs-import')

# -----------------------------------------------------------------
# 3) Onboarding trigger spec: config isOnboardingCompleted -> false
#    (EntryAbility already reads it; just make sure the default path works)
#    No code change needed — the value lives in device files/config.json.
#    We'll toggle it at test time via hdc.
# -----------------------------------------------------------------

# -----------------------------------------------------------------
# 4) ConfirmDialog trigger: BCP navigate to sensitive URL
#    SensitiveOperationDetector.detectNavigation only catches SETTINGS_CHANGE.
#    We need to wire navigate -> detectNavigation result -> requestConfirmation.
#    Currently detectNavigation is called in BrowserShell.onPageEnd but its result
#    is only logged — we need to actually call requestConfirmation + emit SENSITIVE.
# -----------------------------------------------------------------

# In BrowserShell, the detectNavigation call:
old_detect = """            const sensitive = SensitiveOperationDetector.detectNavigation(tabId, url)
            if (sensitive) {
              console.info('BrowserShell sensitive navigation detected: ' + sensitive + ' url=' + url)
            }"""
new_detect = """            const sensitive = SensitiveOperationDetector.detectNavigation(tabId, url)
            if (sensitive) {
              console.info('BrowserShell sensitive navigation detected: ' + sensitive + ' url=' + url)
              // P7: 触发 ConfirmDialog 闭环
              SensitiveOperationDetector.requestConfirmation(tabId, sensitive, url, '').then((ok) => {
                console.info('BrowserShell sensitive confirm resolved: ' + ok + ' url=' + url)
              })
            }"""
patch(BS, old_detect, new_detect, 'bs-detect')

# -----------------------------------------------------------------
# 5) Create test cookies.json
# -----------------------------------------------------------------
cookies = '''[{"domain":"example.com","name":"test_session","value":"p7_cookiexyz123","path":"/","expires":0,"secure":false,"httpOnly":false}]
'''
with io.open(os.path.join(ROOT, 'evidence/p7/test_cookies.json'), 'w', encoding='utf-8') as f:
    f.write(cookies)
print('COOKIES TEST FILE written')

print('\n=== ALL P7-1 PATCHES DONE ===')
