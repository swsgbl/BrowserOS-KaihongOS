const fs = require('fs');
const j = fs.readFileSync('D:\\BrowserOS - KaihongOS\\.verify\\p4_l2.json', 'utf8');
const root = JSON.parse(j);
function walk(n, out) {
  if (!n || typeof n !== 'object') return;
  const a = n.attributes || {};
  if ((a.hint && a.hint.includes('代理')) || (a.text && a.text.includes('P4'))) out.push(JSON.stringify({ hint: a.hint, text: a.text, bounds: a.bounds }));
  (n.children || []).forEach(c => walk(c, out));
}
const out = [];
walk(root, out);
console.log(out.join('\n'));
