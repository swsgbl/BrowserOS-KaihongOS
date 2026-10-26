#!/usr/bin/env node
/* P48: TabStrip 多处出现统一替换（全部替换 + 添加 import + @StorageProp 锚） */
const fs = require('fs')
const F = 'entry/src/main/ets/components/TabStrip.ets'
let s = fs.readFileSync(F, 'utf8')
let n = 0
const sub = (from, to) => {
  const c = s.split(from).length - 1
  if (c === 0) return
  s = s.split(from).join(to)
  n += c
  console.log(`x${c}: ${from.substring(0, 60)}`)
}
sub("tab.title || (tab.agentId ? '代理 ' + tab.agentId.substring(0, 12) : '新标签页')", "tab.title || (tab.agentId ? I18n.t('tabAgent') + ' ' + tab.agentId.substring(0, 12) : I18n.t('tabNewTab'))")
sub(".accessibilityText('关闭标签页 ' + (tab.title || '新标签页'))", ".accessibilityText(I18n.t('tabCloseTab') + ' ' + (tab.title || I18n.t('tabNewTab')))")
sub(".accessibilityText('新建标签页')", ".accessibilityText(I18n.t('menuNewTab'))")
sub(".accessibilityText('搜索标签页')", ".accessibilityText(I18n.t('tabSearchTabs'))")
sub("Text(tab.title || '新标签页')", "Text(tab.title || I18n.t('tabNewTab'))")
sub("Text('新建标签页')", "Text(I18n.t('menuNewTab'))")
// import 注入
if (!s.includes("common/I18n")) {
  const m = s.match(/^import[^\n]*\n/m)
  s = s.replace(m[0], m[0] + "import { I18n } from '../common/I18n'\n")
  console.log('import added after: ' + m[0].trim().substring(0, 60))
}
fs.writeFileSync(F, s)
console.log('total subs: ' + n)
