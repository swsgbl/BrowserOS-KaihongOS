const fs = require('fs');
const c = JSON.parse(fs.readFileSync('C:/Users/hongfu/.hmharness/config.json', 'utf8'));
const provs = c.providers || c.llmProviders || [];
const list = (Array.isArray(provs) ? provs : Object.values(provs)).filter(p => p.baseUrl && String(p.baseUrl).startsWith('https') && (p.apiKey || p.key));

(async () => {
  for (const p of list) {
    const base = String(p.baseUrl).replace(/\/$/, '');
    const key = p.apiKey || p.key;
    const body = JSON.stringify({ model: p.model, messages: [{ role: 'user', content: 'hi' }], max_tokens: 5 });
    try {
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), 25000);
      const r = await fetch(base + '/chat/completions', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key }, body, signal: ctl.signal });
      clearTimeout(timer);
      const text = await r.text();
      let content = '';
      try { const j = JSON.parse(text); content = (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content || '').slice(0, 40); if (!content && j.error) content = 'ERR:' + (j.error.message || '').slice(0, 60); } catch { content = text.slice(0, 60); }
      console.log(`${r.status} ${p.name} ${base} ${p.model} :: ${content}`);
      if (r.status === 200 && content) {
        fs.writeFileSync('C:/Users/hongfu/AppData/Local/Temp/llm_pick.json', JSON.stringify({ baseUrl: base, model: p.model, apiKey: key }));
        console.log('PICKED');
        return;
      }
    } catch (e) {
      console.log(`FAIL ${p.name} ${base} :: ${e.message}`);
    }
  }
  console.log('NONE PASSED');
})();
