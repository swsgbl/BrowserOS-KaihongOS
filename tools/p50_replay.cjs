// P50 重放 SettingsPage 剩余两处补丁(CRLF 兼容)
const fs = require('fs')
const p = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/SettingsPage.ets'
let s = fs.readFileSync(p, 'utf8')

const patches = [
  // 1) navItems 外观置首
  [{
    o: "      { key: 'search', icon: $rawfile('ic_search.svg'), label: I18n.t('stTabSearch') },\n      { key: 'ai', icon: $rawfile('ic_robot.svg'), label: I18n.t('stTabAI') },\n      { key: 'appearance', icon: $rawfile('ic_public.svg'), label: I18n.t('stTabAppearance') },",
    n: "      // P50: 外观置首 —— 默认 navSelection=0 落在外观区,语言切换首屏可见(入口显性化)\n      { key: 'appearance', icon: $rawfile('ic_public.svg'), label: I18n.t('stTabAppearance') },\n      { key: 'ai', icon: $rawfile('ic_robot.svg'), label: I18n.t('stTabAI') },\n      { key: 'search', icon: $rawfile('ic_search.svg'), label: I18n.t('stTabSearch') },"
  }],
  // 2) 右内容区索引映射: 0=外观 2=搜索
  [{
    o: "          if (this.navSelection === 0) {\n            this.SearchSection()\n          } else if (this.navSelection === 1) {\n            this.AiSection()\n          } else if (this.navSelection === 2) {\n            this.AppearanceSection()\n          } else if (this.navSelection === 3) {",
    n: "          if (this.navSelection === 0) {\n            this.AppearanceSection()\n          } else if (this.navSelection === 1) {\n            this.AiSection()\n          } else if (this.navSelection === 2) {\n            this.SearchSection()\n          } else if (this.navSelection === 3) {"
  }]
]

for (const grp of patches) {
  const { o, n } = grp[0]
  const on = o.replace(/\n/g, '\r\n')
  const nn = n.replace(/\n/g, '\r\n')
  const cnt = s.split(on).length - 1
  if (cnt !== 1) { console.log('ANCHOR', cnt, 'FAIL:', o.slice(0, 60)); process.exit(1) }
  s = s.replace(on, nn)
  console.log('patched:', n.slice(0, 50).replace(/\r?\n/g, ' | '))
}
fs.writeFileSync(p, s)

// 验证
const checks = [
  ['navItems appearance 首位', /return \[\r?\n\s*\/\/ P50[^\r\n]*\r?\n\s*\{ key: 'appearance'/],
  ['右区 0=Appearance', /navSelection === 0\) \{\r?\n\s*this\.AppearanceSection\(\)/],
  ['右区 2=Search', /navSelection === 2\) \{\r?\n\s*this\.SearchSection\(\)/],
  ['深链 =2', /navSelection = 2/],
  ['语言卡标题键', /stLangCardTitle/],
  ['胶囊按钮', /Button\(I18n\.t\('stLangZh'\)\)/]
]
let allOk = true
for (const [name, re] of checks) {
  const ok = re.test(s)
  if (!ok) allOk = false
  console.log(ok ? 'PASS' : 'FAIL', name)
}
// 平衡复验
let d = 0, mode = 'code', i = 0
while (i < s.length) {
  const c = s[i], n2 = s[i + 1]
  if (mode === 'code') {
    if (c === '/' && n2 === '/') { mode = 'line'; i += 2; continue }
    if (c === '/' && n2 === '*') { mode = 'block'; i += 2; continue }
    if (c === "'") { mode = 'str'; i++; continue }
    if (c === '`') { mode = 'tstr'; i++; continue }
    if (c === '{') d++; else if (c === '}') d--
  } else if (mode === 'line') { if (c === '\n') mode = 'code' }
  else if (mode === 'block') { if (c === '*' && n2 === '/') { mode = 'code'; i += 2; continue } }
  else if (mode === 'str') { if (c === '\\') { i += 2; continue } if (c === "'") mode = 'code' }
  else if (mode === 'tstr') { if (c === '\\') { i += 2; continue } if (c === '`') mode = 'code' }
  i++
}
console.log('brace balance:', d, allOk && d === 0 ? 'ALL OK' : 'PROBLEM')
