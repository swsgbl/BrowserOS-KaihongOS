// P50 修复:清除两文件尾部竞态注入脏块 + 重放 ChromeWidgets group1 设置置顶补丁
const fs = require('fs')
const proj = 'D:/BrowserOS - KaihongOS'

function cleanAndPatch(file, junkFirstLine, patchPairs) {
  const p = proj + '/' + file
  let s = fs.readFileSync(p, 'utf8')
  const eol = s.includes('\r\n') ? '\r\n' : '\n'
  // 1) 清脏尾:从行首 junkFirstLine 开始到文件尾全部删除
  const lines = s.split(/\r?\n/)
  const ji = lines.findIndex(l => l === junkFirstLine)
  if (ji >= 0) {
    console.log(file, ': junk tail starts at line', ji + 1, '- removing', lines.length - ji, 'lines')
    lines.length = ji
    s = lines.join(eol) + eol
  } else {
    console.log(file, ': no junk first-line found')
  }
  // 2) 重放补丁(精确锚点,必须命中一次)
  for (const [oldS, newS] of patchPairs) {
    const o = oldS.join(eol)
    const n = newS.join(eol)
    const cnt = s.split(o).length - 1
    if (cnt !== 1) { console.log(file, ': ANCHOR COUNT', cnt, '— skip', oldS[0].slice(0, 40)); continue }
    s = s.replace(o, n)
    console.log(file, ': patched —', newS[0].slice(0, 50))
  }
  fs.writeFileSync(p, s)
  // 3) 真实括号平衡(tokenizer 剥字符串/注释)
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
  console.log(file, ': final balance =', d, s.split(/\r?\n/).length, 'lines', d === 0 ? '✓ OK' : '✗ STILL BROKEN')
}

// ChromeWidgets: 脏尾首行 "Done()" + 重放 group1 settings 置顶
cleanAndPatch('entry/src/main/ets/components/ChromeWidgets.ets', 'Done()', [[
  ["      { icon: $rawfile('ic_add.svg'), label: I18n.t('menuNewTab'), action: 'new_tab' },",
   "      { icon: $rawfile('ic_content_copy.svg'), label: I18n.t('menuNewWindow'), action: 'new_window' },"],
  ["      { icon: $rawfile('ic_add.svg'), label: I18n.t('menuNewTab'), action: 'new_tab' },",
   "      // P50: 设置置顶第 2 位 —— 原在 group3 第 9 行,菜单卡 constraintSize(420) 不可滚,实际被裁剪不可见(用户找不到设置入口根因)",
   "      { icon: $rawfile('ic_settings.svg'), label: I18n.t('menuSettings'), action: 'settings' },",
   "      { icon: $rawfile('ic_content_copy.svg'), label: I18n.t('menuNewWindow'), action: 'new_window' },"]
]])

// SettingsPage: 脏尾首行 "e)"
cleanAndPatch('entry/src/main/ets/pages/SettingsPage.ets', 'e)', [])
