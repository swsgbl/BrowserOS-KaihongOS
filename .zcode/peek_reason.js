const fs = require('fs');
const path = 'C:/Users/hongfu/.hmharness/sessions/2026/10/06/' + process.argv[2];
const lines = fs.readFileSync(path, 'utf8').split('\n').filter(Boolean);
const texts = [];
for (const l of lines) {
  try {
    const j = JSON.parse(l);
    if (j.t === 'assistant' && j.text) texts.push((j.time || '').slice(11, 19) + ' :: ' + j.text.slice(0, 250));
  } catch {}
}
texts.slice(-3).forEach(t => console.log(t.replace(/\n/g, ' ')));
