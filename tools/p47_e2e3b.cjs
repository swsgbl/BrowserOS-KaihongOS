/* e2e phase3b: all device-side chained: navigate example.com -> reader */
const { execSync } = require('child_process');
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe';
const T = '192.168.161.137:10178';
function sh(cmd, tmo = 120000) {
  return execSync(`"${HDC}" -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: tmo });
}
function dump(name) {
  execSync(`"${HDC}" -t ${T} shell uitest dumpLayout -p /data/local/tmp/${name}.json`, { encoding: 'utf8', timeout: 30000, stdio: 'pipe' });
  execSync(`"${HDC}" -t ${T} file recv /data/local/tmp/${name}.json evidence/p47/${name}.json`, { encoding: 'utf8', timeout: 30000, stdio: 'pipe' });
  return require('fs').readFileSync(`evidence/p47/${name}.json`, 'utf8');
}
function textsOf(raw) {
  const j = JSON.parse(raw); const t = [];
  (function walk(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); (n.children || []).forEach(walk); })(j);
  return t;
}
function findByText(raw, needle) {
  const j = JSON.parse(raw); let hit = null;
  (function walk(n) {
    const a = n.attributes || {}; const r = a.bounds;
    if (r && a.text && a.text.includes(needle) && !hit) {
      const m = r.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      if (m) hit = { x: (+m[1] + +m[3]) / 2 | 0, y: (+m[2] + +m[4]) / 2 | 0 };
    }
    (n.children || []).forEach(walk);
  })(j);
  return hit;
}

// full chain device-side: click omnibox, type URL with explicit https (avoid search fallback), enter, wait, menu, reader
sh('uinput -T -c 640 400; sleep 1; uinput -T -c 712 61; sleep 1; uitest uiInput text https://example.com/; sleep 1; uitest uiInput keyEvent 2054; sleep 8');
let raw = dump('i1-nav');
console.log('nav:', textsOf(raw).join(' | ').slice(0, 250));
const loaded = textsOf(raw).some(t => t.includes('Example'));
console.log('example loaded:', loaded);

// menu + reader
sh('uinput -T -c 1254 61; sleep 1');
raw = dump('i2-menu');
const rd = findByText(raw, '阅读模式');
console.log('reader item:', JSON.stringify(rd));
if (rd) {
  sh(`uinput -T -c ${rd.x} ${rd.y}; sleep 2`);
  raw = dump('i3-reader');
  console.log('reader view:', textsOf(raw).join(' | ').slice(0, 400));
}
