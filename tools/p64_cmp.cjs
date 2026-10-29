const fs = require('fs');
function walk(n, d = 0, out = []) {
  if (n && typeof n === 'object' && !Array.isArray(n)) {
    const a = n.attributes;
    if (a && typeof a === 'object') out.push([a, d]);
    for (const c of n.children || []) walk(c, d + 1, out);
  } else if (Array.isArray(n)) {
    for (const c of n) walk(c, d, out);
  }
  return out;
}
for (const tag of ['p64_m1', 'p64_free0', 'p64_max0', 'p64r']) {
  if (!fs.existsSync(tag + '_layout.json')) { console.log(tag, 'SKIP no file'); continue; }
  let lay;
  try { lay = JSON.parse(fs.readFileSync(tag + '_layout.json', 'utf-8')); } catch (e) { console.log(tag, 'ERR', e.message); continue; }
  const nodes = walk(lay);
  const btns = [];
  for (const [a, d] of nodes) {
    const m = /^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/.exec(String(a.bounds || ''));
    if (!m) continue;
    const [x1, y1, x2, y2] = m.slice(1).map(Number);
    if (a.type === 'Button' && x1 > 900 && !String(a.id || '').includes('Enhance')) {
      btns.push([y1, x1, x2, y2, a.id || '', d]);
    }
  }
  btns.sort((p, q) => p[0] - q[0] || p[1] - q[1]);
  console.log(`${tag} nodes=${nodes.length} toolbar-Buttons(x1>900)=${btns.length}`);
  for (const b of btns) console.log('   ', JSON.stringify(b));
  // context: parents chain of the rightmost toolbar button
  if (btns.length) {
    const target = btns[btns.length - 1];
    console.log(`   rightmost btn: y1=${target[0]} x1=${target[1]} depth=${target[5]}`);
  }
}
