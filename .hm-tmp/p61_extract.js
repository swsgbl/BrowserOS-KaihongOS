// Extract visible texts from a uitest layout dump
const fs = require('fs');
const file = process.argv[2];
const s = fs.readFileSync(file, 'utf8');
const texts = [];
function walk(node) {
  const a = node.attributes || {};
  if (a.text && a.text.length >= 2) texts.push(a.text.slice(0, 60));
  (node.children || []).forEach(walk);
}
let root;
try { root = JSON.parse(s); } catch (e) {
  const m = s.match(/\"text\":\s*\"([^\"]{2,60})\"/g) || [];
  console.log('RAW_MATCHES:', m.slice(0, 20).join(' | '));
  process.exit(0);
}
walk(root);
console.log('VISIBLE TEXTS (' + texts.length + '):');
texts.slice(0, 25).forEach((t, i) => console.log('  ' + i + ': ' + t));
