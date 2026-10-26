#!/usr/bin/env node
/* P48 修复：字段初始化数组中的 I18n.t() 只求值一次 → 改为 getter 方法 */
const fs = require('fs')

// 1. ChromeWidgets: group1..groupN 数组 → getter
{
  const F = 'entry/src/main/ets/components/ChromeWidgets.ets'
  let s = fs.readFileSync(F, 'utf8')
  const re = /private readonly (group\d+): MenuEntry\[\] = (\[[\s\S]*?\n  \])/
  let n = 0
  let m
  while ((m = re.exec(s))) {
    const getter = `private get ${m[1]}(): MenuEntry[] {\n    return ${m[2].replace(/\n/g, '\n  ')}\n  }`
    s = s.replace(m[0], getter)
    n++
  }
  fs.writeFileSync(F, s)
  console.log('ChromeWidgets: ' + n + ' array fields -> getters')
}
// 2. SettingsPage: navItems → getter
{
  const F = 'entry/src/main/ets/pages/SettingsPage.ets'
  let s = fs.readFileSync(F, 'utf8')
  const re = /private readonly (navItems): NavItem\[\] = (\[[\s\S]*?\n  \])/
  const m = re.exec(s)
  if (m) {
    const getter = `private get ${m[1]}(): NavItem[] {\n    return ${m[2].replace(/\n/g, '\n  ')}\n  }`
    s = s.replace(m[0], getter)
    fs.writeFileSync(F, s)
    console.log('SettingsPage: navItems -> getter')
  } else console.log('SettingsPage: navItems pattern NOT FOUND')
}
// 3. SettingsPage build() 加 localeVersion 锚（P26 模式）
{
  const F = 'entry/src/main/ets/pages/SettingsPage.ets'
  let s = fs.readFileSync(F, 'utf8')
  if (!s.includes('localeVersion < 0')) {
    const anchor = "if (this.themeVersion < 0) {\n          Text('').fontSize(0)\n        }"
    const CRLF = s.includes('\r\n') ? '\r\n' : '\n'
    const a = anchor.replace(/\n/g, CRLF)
    if (s.includes(a)) {
      s = s.replace(a, a + CRLF + '        // P48: localeVersion 渲染依赖锚' + CRLF + '        if (this.localeVersion < 0) {' + CRLF + "          Text('').fontSize(0)" + CRLF + '        }')
      fs.writeFileSync(F, s)
      console.log('SettingsPage: build locale anchor added')
    } else console.log('SettingsPage: themeVersion anchor NOT FOUND (check line endings)')
  } else console.log('SettingsPage: locale anchor exists')
}
// 4. SidebarRail: rail items 若是字段数组同样处理
{
  const F = 'entry/src/main/ets/components/SidebarRail.ets'
  let s = fs.readFileSync(F, 'utf8')
  const re = /private (readonly )?(items|RailItem\[\]|railItems)/
  if (re.test(s) && /I18n\.t\(/.test(s)) {
    const arrRe = /private (?:readonly )?(items|railItems): \w+\[\] = (\[[\s\S]*?\n  \])/
    const m = arrRe.exec(s)
    if (m) {
      const getter = `private get ${m[1]}(): any[] {\n    return ${m[2].replace(/\n/g, '\n  ')}\n  }`
      s = s.replace(m[0], getter)
      fs.writeFileSync(F, s)
      console.log('SidebarRail: ' + m[1] + ' -> getter')
    } else console.log('SidebarRail: array field pattern not found (may be inline)')
  } else console.log('SidebarRail: inline items, no field array')
}
