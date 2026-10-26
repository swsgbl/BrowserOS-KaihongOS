// P50 诊断:两文件大括号平衡异常(-2/-6)但表面无错 —— 逐 struct 定界找缺失开括号的实体
const fs = require('fs')

function scan(f) {
  const s = fs.readFileSync(f, 'utf8')
  const lines = s.split(/\r?\n/)
  let depth = 0
  let lastTop = 0
  const evts = [] // {line, depth, label}
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i]
    const m = l.match(/(export\s+)?struct\s+(\w+)/)
    if (m) { evts.push({ line: i + 1, depth, label: 'struct ' + m[2] + ' OPEN', d0: depth }) }
    const cm = l.match(/@Builder\s*$/)
    for (const c of l) {
      if (c === '{') depth++
      else if (c === '}') depth--
    }
    if (depth < 0 && lastTop === 0) { lastTop = i + 1; evts.push({ line: i + 1, depth, label: 'NEGATIVE DEPTH first at' }) }
  }
  console.log('==', f, 'final depth:', depth)
  for (const e of evts) console.log(' ', e.line, e.label, '(depth before open:', e.d0 !== undefined ? e.d0 : e.depth, ')')
}

scan('D:/BrowserOS - KaihongOS/entry/src/main/ets/components/ChromeWidgets.ets')
scan('D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/SettingsPage.ets')
