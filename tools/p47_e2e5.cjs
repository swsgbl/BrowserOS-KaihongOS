/* e2e5: eval "6*7" — no + encoding issue; Enter via keyEvent 2050 */
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
function textsOf(raw) {
  const j = JSON.parse(raw); const t = [];
  (function walk(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); (n.children || []).forEach(walk); })(j);
  return t;
}

// clear existing "1%2B1" first: select-all via long click not easy; just append Enter? text has %2B.
// Simplest: inputText replaces? It appends at focus. Use backspaces via keyEvent 2053 (backspace)? messy.
// Use ctrl+A: no. Try inputText at same coords with new text - it sets value (native setter) per docs "input text at coordinate"
sh('uitest uiInput inputText 534 715 6*7; sleep 1');
sh('uitest uiInput keyEvent 2050; sleep 2');
let raw = dump('g5-eval');
console.log('after eval:', textsOf(raw).join(' | ').slice(0, 600));
