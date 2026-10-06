const fs = require('fs');
const j = fs.readFileSync('D:\\BrowserOS - KaihongOS\\.verify\\p4_l2.json', 'utf8');
const root = JSON.parse(j);
console.log('root keys: ' + Object.keys(root).join(','));
function walk(n, depth, out) {
  if (!n || typeof n !== 'object') return;
  const a = n.attributes || {};
  if (a.text && a.text.trim().length >= 2) out.push(a.text.trim() + ' @ ' + a.bounds + (a.clickable === 'true' ? ' [CLICK]' : ''));
  const kids = n.children || [];
  kids.forEach(c => walk(c, depth + 1, out));
}
const out = [];
walk(root, 0, out);
console.log(out.length + ' texts');
console.log(out.join('\n'));
