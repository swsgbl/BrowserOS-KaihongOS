// P50: 剥离字符串/注释后的真实大括号平衡 + 与 git HEAD 对比
const fs = require('fs')
const { execSync } = require('child_process')

function realBalance(s) {
  let depth = 0
  let i = 0
  let mode = 'code' // code | line | block | str | tstr
  while (i < s.length) {
    const c = s[i]
    const n = s[i + 1]
    if (mode === 'code') {
      if (c === '/' && n === '/') { mode = 'line'; i += 2; continue }
      if (c === '/' && n === '*') { mode = 'block'; i += 2; continue }
      if (c === "'") { mode = 'str'; i++; continue }
      if (c === '`') { mode = 'tstr'; i++; continue }
      if (c === '{') depth++
      else if (c === '}') depth--
    } else if (mode === 'line') {
      if (c === '\n') mode = 'code'
    } else if (mode === 'block') {
      if (c === '*' && n === '/') { mode = 'code'; i += 2; continue }
    } else if (mode === 'str') {
      if (c === '\\') { i += 2; continue }
      if (c === "'") mode = 'code'
    } else if (mode === 'tstr') {
      if (c === '\\') { i += 2; continue }
      if (c === '`') mode = 'code'
    }
    i++
  }
  return depth
}

const files = [
  'entry/src/main/ets/components/ChromeWidgets.ets',
  'entry/src/main/ets/pages/SettingsPage.ets'
]
const proj = 'D:/BrowserOS - KaihongOS'
for (const f of files) {
  const now = fs.readFileSync(proj + '/' + f, 'utf8')
  const head = execSync('git show HEAD:"' + f + '"', { cwd: proj }).toString()
  console.log(f)
  console.log('  HEAD balance:', realBalance(head), ' lines:', head.split(/\r?\n/).length)
  console.log('  NOW  balance:', realBalance(now), ' lines:', now.split(/\r?\n/).length)
}
