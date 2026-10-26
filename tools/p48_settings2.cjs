#!/usr/bin/env node
/* P48: SettingsPage 动态拼接手动处理 + 语言切换卡片 */
const fs = require('fs')
const F = 'entry/src/main/ets/pages/SettingsPage.ets'
let s = fs.readFileSync(F, 'utf8')
const subs = [
  // 动态计数（改 I18n 拼接）
  ["Text(this.cntHistory + ' 条')", "Text(I18n.t('ntBmCount') === '书签 ' ? this.cntHistory + ' 条' : this.cntHistory + '')"],
]
// 逐条唯一替换
function rep(from, to) {
  const n = s.split(from).length - 1
  if (n !== 1) { console.log('MISS(' + n + '): ' + from.substring(0, 70)); return }
  s = s.replace(from, to)
}
// 简单计数条目：zh 保持原格式，en 空尾
rep("Text(this.cntHistory + ' 条')", "Text('' + this.cntHistory + I18n.t('ntCountEnd'))")
rep("Text(this.cntBookmarks + ' 条')", "Text('' + this.cntBookmarks + I18n.t('ntCountEnd'))")
rep("Text(this.cntLogins + ' 个域名')", "Text(I18n.t('stDomainN').replace('{n}', '' + this.cntLogins))")
rep("Text(this.cntDownloads + ' 项')", "Text(I18n.t('stDownloadN').replace('{n}', '' + this.cntDownloads))")
rep("this.mcpCopiedHint = '已复制'", "this.mcpCopiedHint = I18n.t('copied')")
rep("this.llmSaveHint = `${m} 连接成功 (${ms}ms)`", "this.llmSaveHint = `${m}${I18n.t('stConnOk')}${ms}${I18n.t('stConnOkEnd')}`")
rep(".fontColor((this.llmSaveHint === '已保存' || this.llmSaveHint.includes('连接成功'))", ".fontColor((this.llmSaveHint === I18n.t('saved') || this.llmSaveHint.includes(I18n.t('testConn').length > 0 ? '连接成功' : '连接成功'))")
rep("Text(`服务状态：${MCPServer.isRunning() ? '运行中 · 端口 ' + MCPServer.getPort() : '未启动'}`)", "Text(I18n.t('stMcpStatus') + (MCPServer.isRunning() ? I18n.t('stMcpRunning') + MCPServer.getPort() : I18n.t('stMcpStopped')))")
rep("this.CardShell('BrowserOS for KaihongOS', '给 AI 代理用的浏览器')", "this.CardShell(I18n.t('stAboutCard'), I18n.t('stAboutDesc'))")
rep("Text('版本')", "Text(I18n.t('stVersion'))")
rep("Text('构建')", "Text(I18n.t('stBuild'))")

// import + 刷新锚
if (!s.includes("common/I18n")) {
  const m = s.match(/^import[^\n]*\n/m)
  s = s.replace(m[0], m[0] + "import { I18n } from '../common/I18n'\n")
  console.log('import added')
}
const anchor = "@StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44"
if (s.includes(anchor) && !s.includes("app_locale")) {
  s = s.replace(anchor, anchor + "\n  // P48: locale 刷新锚\n  @StorageProp('app_locale') @Watch('onLocaleFlip2') appLocale: string = 'zh'\n  @State localeVersion: number = 0\n\n  onLocaleFlip2(): void {\n    this.localeVersion++\n  }")
  console.log('anchor added')
}
fs.writeFileSync(F, s)
console.log('done')
