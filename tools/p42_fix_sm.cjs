// P42 fix: SessionManager ArkTS 匿名类型 → 显式类
const fs = require('fs')
const f = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/SessionManager.ets'
let c = fs.readFileSync(f, 'utf8')
if (!c.includes('class SessionFileTime')) {
  const anchor = 'interface SessionStartData {'
  const cls = [
    '/** P42 (KAI-061): 会话文件时间戳载体（ArkTS 禁匿名对象类型，显式类） */',
    'class SessionFileTime {',
    "  file: string = ''",
    '  startTime: number = -1',
    '}',
    ''
  ].join('\n')
  c = c.replace(anchor, cls + '\n' + anchor)
}
c = c.replace('const timed: { file: string, startTime: number }[] = []',
  'const timed: SessionFileTime[] = []')
c = c.replace('timed.push({ file: f, startTime: st })',
  "const t = new SessionFileTime()\n      t.file = f\n      t.startTime = st\n      timed.push(t)")
fs.writeFileSync(f, c, 'utf8')
const v = fs.readFileSync(f, 'utf8').split(/\r?\n/)
v.forEach((l, i) => { if (/SessionFileTime|timed\.push/.test(l)) console.log((i + 1) + ': ' + l) })
