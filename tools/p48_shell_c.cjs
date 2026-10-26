#!/usr/bin/env node
/* P48: BrowserShell 收尾 —— 4 处残留 + import + 刷新锚 */
const fs = require('fs')
const F = 'entry/src/main/ets/pages/BrowserShell.ets'
let s = fs.readFileSync(F, 'utf8')
function rep(from, to) {
  const n = s.split(from).length - 1
  if (n !== 1) { console.log('MISS(' + n + '): ' + from.substring(0, 70)); return }
  s = s.replace(from, to)
  console.log('OK: ' + from.substring(0, 60))
}
rep("icon: $rawfile('ic_back.svg'), label: '后退', enabled:", "icon: $rawfile('ic_back.svg'), label: I18n.t('tbBack'), enabled:")
rep("items.push({ kind: 'search', title: getEngineById(ConfigManager.getSearchEngineId()).name + ' 搜索 ' + kw, url: kw })", "items.push({ kind: 'search', title: getEngineById(ConfigManager.getSearchEngineId()).name + (I18n.getLocale() === 'en' ? ' Search ' : ' 搜索 ') + kw, url: kw })")
rep("this.p47SaveUser = u.length > 0 ? u : '(未知用户名)'", "this.p47SaveUser = u.length > 0 ? u : I18n.t('pwUnknownUser')")
rep("const user = this.p47SaveUser === '(未知用户名)' ? '' : this.p47SaveUser", "const user = this.p47SaveUser === '(未知用户名)' || this.p47SaveUser === '(unknown username)' ? '' : this.p47SaveUser")
// 2762 js 注入串不动（发给页面的 JS，非 UI）
// import
if (!s.includes("common/I18n")) {
  const m = s.match(/^import[^\n]*\n/m)
  s = s.replace(m[0], m[0] + "import { I18n } from '../common/I18n'\n")
  console.log('import added')
}
// 刷新锚：挂在 darkMode 锚之后
const anchor = "@StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false"
if (s.includes(anchor) && !s.includes("app_locale")) {
  s = s.replace(anchor, anchor + "\n  // P48: locale 刷新锚（语言切换时全树重渲染，同 themeVersion 模式）\n  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'\n  @State localeVersion: number = 0")
  // onThemeFlip 方法后加 onLocaleFlip
  const flipFn = /onThemeFlip\(\): void \{\n    this\.themeVersion\+\+\n[^\n]*\n  \}/m
  const fm = s.match(flipFn)
  if (fm) {
    s = s.replace(fm[0], fm[0] + "\n\n  // P48: 语言切换钩子 —— 递增 localeVersion 驱动全树重渲染\n  onLocaleFlip(): void {\n    this.localeVersion++\n    console.info('BrowserShell locale flipped: ' + this.appLocale)\n  }")
    console.log('onLocaleFlip added')
  }
  console.log('anchor added')
}
fs.writeFileSync(F, s)
console.log('done')
