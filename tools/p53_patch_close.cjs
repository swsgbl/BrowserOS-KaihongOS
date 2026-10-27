// P53: closeTabById 关闭无痕标签时清无痕 cookie 管理器（不残留）
const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/BrowserShell.ets'
let t = fs.readFileSync(P, 'utf8')
const anchor = "  private closeTabById(tabId: string): void {\r\n    this.controllers.delete(tabId)"
if (!t.includes(anchor)) { console.error('MISS closeTabById'); process.exit(1) }
const inject = "  private closeTabById(tabId: string): void {\r\n" +
  "    // P53: 无痕标签关闭 —— 清全局无痕 cookie 存储（防止残留）\r\n" +
  "    if (this.p47IncognitoTabs.has(tabId)) {\r\n" +
  "      try {\r\n" +
  "        webview.WebCookieManager.clearAllCookiesSync(true)\r\n" +
  "        console.info('[P53] incognito tab closed, incognito cookies cleared: ' + tabId)\r\n" +
  "      } catch (e) {\r\n" +
  "        console.warn('[P53] clear incognito cookies failed: ' + e)\r\n" +
  "      }\r\n" +
  "      this.p47IncognitoTabs.delete(tabId)\r\n" +
  "    }\r\n" +
  "    this.controllers.delete(tabId)"
t = t.replace(anchor, inject)
fs.writeFileSync(P, t, 'utf8')
const v = fs.readFileSync(P, 'utf8')
if (!v.includes('clearAllCookiesSync(true)')) { console.error('VERIFY FAIL'); process.exit(1) }
console.log('OK: closeTabById incognito cleanup added')
