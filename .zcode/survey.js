const fs = require('fs');
const dir = 'C:/Users/hongfu/.hmharness/sessions';
const files = [];
(function walk(d) {
  try { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = d + '/' + e.name; if (e.isDirectory()) walk(p); else if (e.name.endsWith('.jsonl') && fs.statSync(p).size > 50000) files.push(p); } } catch {}
})(dir);
files.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
const f = files[0];
console.log('FILE:', f);
const lines = fs.readFileSync(f, 'utf8').split('\n').filter(Boolean);
const texts = [];
for (const l of lines) {
  try { const j = JSON.parse(l); if (j.t === 'assistant' && j.text) texts.push((j.time || '').slice(11, 19) + ' :: ' + j.text.slice(0, 200)); } catch {}
}
texts.slice(-6).forEach(t => console.log(t.replace(/\n/g, ' ')));
