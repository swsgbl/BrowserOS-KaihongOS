/* e2e phase3: verify reader + form fill + zoom toast menu entries; navigate to example.com and test zoom/reader */
const { execSync } = require('child_process');
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe';
const T = '192.168.161.137:10178';
function sh(cmd, tmo = 90000) {
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

// wait app boot
execSync('sleep 3');

// 1. open menu, check entries
sh('uinput -T -c 1254 61; sleep 1');
let raw = dump('h1-menu');
let it = findByText(raw, '阅读模式');
const fill = findByText(raw, '填充表单');
console.log('reader item:', JSON.stringify(it), 'fill item:', JSON.stringify(fill));
if (!it || !fill) { console.log('texts:', textsOf(raw).join(' | ').slice(0, 400)); process.exit(1); }

// 2. navigate to example.com first (for reader test we need content)
// omnibox at ~(712,61)
sh('uinput -T -c 640 400; sleep 1'); // dismiss menu by clicking empty
sh('uinput -T -c 712 61; sleep 1');
sh('uitest uiInput text https://example.com; sleep 1; uitest uiInput keyEvent 2050; sleep 6');
raw = dump('h2-navigated');
const texts = textsOf(raw);
console.log('after nav:', texts.join(' | ').slice(0, 300));
const hasExample = texts.some(t => t.includes('Example Domain') || t.includes('example.com'));
console.log('example.com loaded:', hasExample);

// 3. zoom in via menu
sh('uinput -T -c 1254 61; sleep 1');
raw = dump('h3-menu2');
const zoomIn = findByText(raw, '放大');
console.log('zoom_in item:', JSON.stringify(zoomIn));
if (zoomIn) {
  sh(`uinput -T -c ${zoomIn.x} ${zoomIn.y}; sleep 1`);
  raw = dump('h4-zoomed');
  console.log('after zoom:', textsOf(raw).join(' | ').slice(0, 250));
}

// 4. reader mode on example.com (has <p> content)
sh('uinput -T -c 1254 61; sleep 1');
raw = dump('h5-menu3');
const rd = findByText(raw, '阅读模式');
if (rd) {
  sh(`uinput -T -c ${rd.x} ${rd.y}; sleep 2`);
  raw = dump('h6-reader');
  console.log('reader view:', textsOf(raw).join(' | ').slice(0, 350));
}
console.log('E2E PHASE3 DONE');
