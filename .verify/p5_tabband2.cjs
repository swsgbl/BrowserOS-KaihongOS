const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
execSync(`${HDC} -t ${T} shell "uitest dumpLayout -p /data/local/tmp/p5_g.json"`, { encoding: 'utf8', maxBuffer: 40e6 });
const j = execSync(`${HDC} -t ${T} shell "cat /data/local/tmp/p5_g.json"`, { encoding: 'utf8', maxBuffer: 40e6 });
const o = JSON.parse(j);
const hits = [];
(function walk(n, depth) {
  if (!n || typeof n !== 'object') return;
  const a = n.attributes || {};
  const b = a.bounds || '';
  const m = b.match(/\[([\d.]+),([\d.]+)\]\[([\d.]+),([\d.]+)\]/);
  if (m) {
    const y1 = parseFloat(m[2]), y2 = parseFloat(m[4]), x1 = parseFloat(m[1]);
    if (y1 >= 264 && y2 <= 302 && x1 > 490) hits.push({ depth, type: a.type, text: (a.text || '').slice(0, 30), b });
  }
  (n.children || []).forEach(c => walk(c, depth + 1));
})(o, 0);
hits.sort((p, q) => p.depth - q.depth);
hits.forEach(h => console.log(' '.repeat(h.depth) + h.type + ' | "' + h.text + '" | ' + h.b));
