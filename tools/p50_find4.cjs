// P50 定位器: bounds 字段 + type/text/id 多条件
const fs = require('fs')
const j = JSON.parse(fs.readFileSync('D:/BrowserOS - KaihongOS/evidence/p50/layout.json', 'utf8'))
const kw = process.argv[2] || ''
const typ = process.argv[3] || ''
const hits = []
function search(n, depth) {
  const a = n.attributes || {}
  const s = kw ? (a['text'] || '') + (a['id'] || '') + (a['description'] || '') : ''
  if ((!kw || s.includes(kw)) && (!typ || a['type'] === typ)) {
    hits.push({ d: depth, t: a['type'], id: a['id'], text: (a['text'] || '').slice(0, 24), b: a['bounds'] })
  }
  for (const c of (n.children || [])) search(c, depth + 1)
}
search(j, 0)
console.log('hits:', hits.length)
for (const h of hits.slice(0, 30)) console.log(JSON.stringify(h))
