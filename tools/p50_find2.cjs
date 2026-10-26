// P50: 在 layout.json 中找包含关键词的节点(多关键词 or 搜索)
const fs = require('fs')
const j = JSON.parse(fs.readFileSync('D:/BrowserOS - KaihongOS/evidence/p50/layout.json', 'utf8'))
const kw = process.argv[2]
const hits = []
function search(n, depth) {
  const a = n.attributes || {}
  const s = JSON.stringify(a)
  if (kw === '*' || (kw && s.includes(kw))) {
    hits.push({ d: depth, type: n.type, id: a['id'], text: (a['text'] || '').slice(0, 20), rect: a['rect'] })
  }
  for (const c of (n.children || [])) search(c, depth + 1)
}
search(j, 0)
console.log('hits:', hits.length)
for (const h of hits.slice(0, 20)) console.log(JSON.stringify(h))
