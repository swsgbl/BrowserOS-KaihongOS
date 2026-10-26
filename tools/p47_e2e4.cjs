/* e2e4: eval 1+1 via uitest inputText device-side */
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

// devtools open, input at (534,715). inputText clicks? It inputs at coordinate (focuses + types)
sh('uitest uiInput inputText 534 715 1%2B1; sleep 1');
// Enter via keyEvent 2054? Enter key id. Use keyEvent with KEYCODE_ENTER = 2050? Standard OH: 2050=ENTER? Try 2098? Just use uinput? Use keyEvent Enter name not in list.
// List shows keyEvent <keyID/Back/Home/Power>. KEY_ENTER on OH is 2050. Try it, fallback 2099.
let raw = dump('g4-typed');
console.log('after type:', textsOf(raw).join(' | ').slice(0, 500));
