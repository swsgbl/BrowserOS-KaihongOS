/* e2e zoom: menu -> 放大 (single flow, dump-guided) */
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
function textsOf(raw) {
  const j = JSON.parse(raw); const t = [];
  (function walk(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); (n.children || []).forEach(walk); })(j);
  return t;
}

// ensure foreground
sh('aa start -a EntryAbility -b com.browseros.kaihong');
execSync('sleep 2');
// menu open + zoom click in one device-side chain
sh('uinput -T -c 1254 61; sleep 1');
let raw = dump('j1-menu');
const zi = findByText(raw, '放大');
console.log('zoom item:', JSON.stringify(zi));
if (!zi) { console.log(textsOf(raw).join(' | ').slice(0, 300)); process.exit(1); }
sh(`uinput -T -c ${zi.x} ${zi.y}; sleep 1`);
raw = dump('j2-zoomtoast');
console.log('after zoom:', textsOf(raw).join(' | ').slice(0, 300));
