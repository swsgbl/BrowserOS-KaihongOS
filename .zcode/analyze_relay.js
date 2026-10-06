const fs = require('fs');
const lines = fs.readFileSync('C:/Users/hongfu/.hmharness/sessions/2026/10/06/2026-10-05T16-15-25-he6s31.jsonl', 'utf8').split('\n').filter(Boolean);
console.log('total events:', lines.length);
// count event types and tokens
let tokens = 0, turns = 0, toolUses = 0;
const types = {};
for (const l of lines) {
  try {
    const j = JSON.parse(l);
    types[j.t] = (types[j.t] || 0) + 1;
    if (j.t === 'final') { tokens = j.tokens || j.usage?.total_tokens || 0; turns = j.turns || 0; toolUses = j.toolUses || 0; }
  } catch {}
}
console.log('event types:', JSON.stringify(types));
console.log('final: turns=' + turns + ' toolUses=' + toolUses + ' tokens=' + tokens);
// search for provider errors / context signals
const sigs = ['exceed', 'overflow', 'too long', 'maximum context', 'context length', 'token limit', '400', '413'];
outer: for (let i = lines.length - 1; i >= Math.max(0, lines.length - 60); i--) {
  for (const s of sigs) {
    if (lines[i].toLowerCase().includes(s.toLowerCase())) {
      console.log('SIGNAL line ' + i + ': ' + lines[i].slice(0, 300));
      continue outer;
    }
  }
}
// last 3 assistant texts
const texts = [];
for (const l of lines) {
  try { const j = JSON.parse(l); if (j.t === 'assistant' && j.text) texts.push(j.time + ' :: ' + j.text.slice(0, 150)); } catch {}
}
console.log('--- last 3 assistant texts ---');
texts.slice(-3).forEach(t => console.log(t.replace(/\n/g, ' ')));
