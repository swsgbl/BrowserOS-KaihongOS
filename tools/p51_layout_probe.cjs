const fs = require('fs')
const raw = fs.readFileSync(process.argv[2], 'utf8')
const nodes = raw.split('"attributes":{').slice(1)
for (const n of nodes) {
  const seg = n.slice(0, 1200)
  const tm = seg.match(/"type":"TextInput"/)
  if (!tm) continue
  const bm = seg.match(/"bounds":"\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/)
  const vm = seg.match(/"text":"([^"]{0,80})"/)
  const hm = seg.match(/"hint":"([^"]{0,80})"/)
  console.log(`TextInput@[${bm ? bm[1] + ',' + bm[2] : '?'}] text=${vm ? JSON.stringify(vm[1]) : '(none)'} hint=${hm ? JSON.stringify(hm[1]) : '(none)'}`)
}
