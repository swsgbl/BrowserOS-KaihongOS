/* e2e6: backspace-clear then type 6*7, Enter 2050 */
const { execSync } = require('child_process');
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe';
const T = '192.168.161.137:10178';
function sh(cmd, tmo = 60000) {
  return execSync(`"${HDC}" -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: tmo });
}
function dump(name) {
  execSync(`"${HDC}" -t ${T} shell uitest dumpLayout -p /data/local/tmp/${name}.json`, { encoding: 'utf8', timeout: 30000, stdio: 'pipe' });
  execSync(`"${HDC}" -t ${T} file recv /data/local/tmp/${name}.json evidence/p47/${name}.json`, { encoding: 'utf8', timeout: 30000, stdio:'pipe' });
  return require('fs').readFileSync(`evidence/p47/${name}.json`, 'utf8');
}
function textsOf(raw) {
  const j = JSON.parse(raw); const t = [];
  (function walk(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); (n.children || []).forEach(walk); })(j);
  return t;
}

let chain = '';
for (let i = 0; i < 14; i++) chain += 'uitest uiInput keyEvent 2053; ';
sh(chain + 'sleep 1');
sh('uitest uiInput inputText 534 715 6*7; sleep 1');
sh('uitest uiInput keyEvent 2050; sleep 2');
const raw = dump('g6-eval2');
console.log('after eval:', textsOf(raw).join(' | ').slice(0, 600));
