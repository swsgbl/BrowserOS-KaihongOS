// P50: dumpLayout attributes 是对象非数组(记忆坑)——直接递归 attributes 字段
const fs = require('fs')
const j = JSON.parse(fs.readFileSync('D:/BrowserOS - KaihongOS/evidence/p50/layout.json', 'utf8'))
const kw = process.argv[2] || ''
const mode = process.argv[3] || 'all' // all | attr | image
const hits = []
function search(n, depth) {
  const a = n.attributes || {}
  const rect = a['rect'] || ''
  if (mode === 'image' && n.type === 'Image' && rect) {
    hits.push({ d: depth, t: n.type, rect })
  } else if (mode !== 'image') {
    const s = JSON.stringify(a)
    if (!kw || s.includes(kw)) hits.push({ d: depth, t: n.type, id: a['id'], text: (a['text'] || '').slice(0, 24), rect })
  }
  for (const c of (n.children || [])) search(c, depth + 1)
}
search(j, 0)
console.log('hits:', hits.length)
for (const h of hits.slice(0, 30)) console.log(JSON.stringify(h))
