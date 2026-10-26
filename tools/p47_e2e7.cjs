/* e2e7: click input first, clear via repeated backspace, then type+enter */
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

// click input, clear (20 backspaces), type, enter — all device-side
sh('uinput -T -c 534 715; sleep 1');
let bs = '';
for (let i = 0; i < 20; i++) bs += 'uitest uiInput keyEvent 2053; ';
sh(bs + 'sleep 1; uitest uiInput text 6*7; sleep 1; uitest uiInput keyEvent 2050; sleep 2');
const raw = dump('g7-eval3');
console.log('result:', textsOf(raw).join(' | ').slice(0, 600));
