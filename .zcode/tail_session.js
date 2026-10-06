const fs = require('fs');
const file = process.argv[2];
const n = parseInt(process.argv[3] || '6', 10);
const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
const texts = [];
for (const l of lines) {
  try {
    const j = JSON.parse(l);
    if (j.t === 'assistant') {
      let s = (j.text || '').slice(0, 200);
      if (j.tool_calls) s += ' [call:' + j.tool_calls.map(c => c.function.name).join(',') + ']';
      texts.push(j.time + ' :: ' + s);
    } else if (j.t === 'tool') {
      texts.push(j.time + ' >> ' + (j.output || '').slice(0, 150));
    }
  } catch {}
}
texts.slice(-n).forEach(t => console.log(t.replace(/\r?\n/g, ' ')));
