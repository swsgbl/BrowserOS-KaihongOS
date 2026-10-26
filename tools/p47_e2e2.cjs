/* e2e v2: devtools console verify — device-side chained clicks to avoid host latency */
const { execSync } = require('child_process');
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe';
const T = '192.168.161.137:10178';
function sh(cmd, tmo = 60000) {
  return execSync(`"${HDC}" -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: tmo });
}
function dump(name) {
  execSync(`"${HDC}" -t ${T} shell uitest dumpLayout -p /data/local/tmp/${name}.json`, { encoding: 'utf8', timeout: 30000, stdio: 'pipe' });
  execSync(`"${HDC}" -t ${T} file recv /data/local/tmp/${name}.json evidence/p47/${name}.json`, { encoding: 'utf8', timeout: 30000, stdio: 'pipe' });
  return require('fs').readFileSync(`evidence/p47/${name}.json`, 'utf8');
}
function findByText(raw, needle) {
  const j = JSON.parse(raw);
  let hit = null;
  (function walk(n) {
    const a = n.attributes || {};
    const r = a.bounds;
    if (r && a.text && a.text.includes(needle) && !hit) {
      const m = r.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      if (m) hit = { x: (+m[1] + +m[3]) / 2 | 0, y: (+m[2] + +m[4]) / 2 | 0, t: a.text };
    }
    (n.children || []).forEach(walk);
  })(j);
  return hit;
}

// device-side chain: click empty area (close omnibox focus), open menu
sh('uinput -T -c 640 400; sleep 1; uinput -T -c 1254 61; sleep 1');
const raw = dump('g1-menu');
const dt = findByText(raw, '开发者工具');
console.log('devtools item:', JSON.stringify(dt));
if (!dt) {
  const texts = [];
  (function walk(n) { if (n.attributes && n.attributes.text) texts.push(n.attributes.text); (n.children || []).forEach(walk); })(JSON.parse(raw));
  console.log('texts:', texts.join(' | ').slice(0, 300));
  process.exit(1);
}
// click devtools device-side
sh(`uinput -T -c ${dt.x} ${dt.y}; sleep 2`);
const raw2 = dump('g2-devtools');
const texts2 = [];
(function walk(n) { if (n.attributes && n.attributes.text) texts2.push(n.attributes.text); (n.children || []).forEach(walk); })(JSON.parse(raw2));
console.log('devtools page:', texts2.join(' | ').slice(0, 400));
