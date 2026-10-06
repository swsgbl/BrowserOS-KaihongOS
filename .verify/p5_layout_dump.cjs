const fs = require('fs');
const d = JSON.parse(fs.readFileSync('.verify/p5_layout.json', 'utf8'));
const out = [];
function walk(n) {
  if (n.attributes && n.attributes.text && n.attributes.text.length > 0) {
    const a = n.attributes;
    out.push(a.text + ' | ' + (a.bounds || 'no-bounds'));
  }
  if (n.children) for (const c of n.children) walk(c);
}
walk(d);
console.log(out.join('\n'));
