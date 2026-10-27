// P53: BrowserShell profileType 接线（CRLF node 补丁）
const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/BrowserShell.ets'
let t = fs.readFileSync(P, 'utf8')
let n = 0
function rep(oldStr, newStr, label, opt) {
  const o = oldStr.replace(/\n/g, '\r\n')
  const nw = newStr.replace(/\n/g, '\r\n')
  if (!t.includes(o)) {
    if (opt === 'soft') { console.log('SKIP: ' + label); return }
    console.error('MISS: ' + label); process.exit(1)
  }
  t = t.split(o).join(nw); n++
}

// 1. Web 组件 incognitoMode 从 p47 集合查询改为 TabInfo 字段（保持 p47 集合兼容——双源）
rep("Web({ src: 'about:blank', controller: this.getOrCreateController(tab.tabId), incognitoMode: this.p47IncognitoTabs.has(tab.tabId) })",
    "Web({ src: 'about:blank', controller: this.getOrCreateController(tab.tabId), incognitoMode: this.p47IncognitoTabs.has(tab.tabId) || tab.isIncognito() })",
    'web incognitoMode')

// 2. p47CreateIncognitoTab 设置 profileType
rep("    this.p47IncognitoTabs.add(tab.tabId)\n    this.tabs = TabManager.getAllTabs()",
    "    this.p47IncognitoTabs.add(tab.tabId)\n    // P53: profileType 统一标记（TabInfo 持久化，MCP/会话路由可见）\n    tab.profileType = 'incognito'\n    TabManager.updateTabUrl(tab.tabId, tab.currentUrl)\n    this.tabs = TabManager.getAllTabs()",
    'create incognito set profileType')

fs.writeFileSync(P, t, 'utf8')
const v = fs.readFileSync(P, 'utf8')
if (!v.includes("tab.profileType = 'incognito'") || !v.includes('tab.isIncognito()')) { console.error('VERIFY FAIL'); process.exit(1) }
console.log('OK: BrowserShell patched (' + n + ' edits)')
