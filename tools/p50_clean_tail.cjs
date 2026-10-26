// P50: 清除 SettingsPage.ets 尾部注入的脏块(截断注入坑,与 P23 ScheduleManager 同型)
const fs = require('fs')
const f = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/SettingsPage.ets'
let s = fs.readFileSync(f, 'utf8')
const lines = s.split(/\r?\n/)
// 文件应以 "}" (struct 结束) 收尾;找到最后一个 "}" 行之后的内容
let last = -1
for (let i = lines.length - 1; i >= 0; i--) {
  if (lines[i].trim() === '}') { last = i; break }
}
console.log('last struct-closing } at line', last + 1, 'of', lines.length)
if (last >= 0 && last < lines.length - 1) {
  const tail = lines.slice(last + 1).join('\n')
  console.log('removing trailing junk:', JSON.stringify(tail.slice(0, 120)))
  s = lines.slice(0, last + 1).join('\r\n') + '\r\n'
  fs.writeFileSync(f, s)
  console.log('written, new line count:', s.split(/\r?\n/).length)
} else {
  console.log('no trailing junk detected')
}
// 验证括号平衡
let d = 0
for (const c of s) { if (c === '{') d++; if (c === '}') d-- }
console.log('brace balance now:', d)
