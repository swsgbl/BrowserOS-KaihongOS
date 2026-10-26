/* e2e3: JS eval in devtools console via uitest keyboard input */
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
function findInput(raw) {
  const j = JSON.parse(raw); let hit = null;
  (function walk(n) {
    const a = n.attributes || {}; const r = a.bounds;
    if (r && a.type === 'TextInput' && !hit) {
      const m = r.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      if (m && +m[4] > 700) hit = { x: (+m[1] + +m[3]) / 2 | 0, y: (+m[2] + +m[4]) / 2 | 0 };
    }
    (n.children || []).forEach(walk);
  })(j);
  return hit;
}

// devtools page is open (from e2e2). find TextInput at bottom
let raw = dump('g3-console');
let input = findInput(raw);
console.log('eval input:', JSON.stringify(input));
if (!input) { console.log('texts:', textsOf(raw).join(' | ').slice(0, 300)); process.exit(1); }

// click input, then type 1+1 using uinput key simulation via "shell uinput -T -m" drag? No.
// Device API: uitest has no text input from host. Use keyboard: hdc shell "uitest uiInput keyEvent"?
// KaihongOS supports: uinput -T -c ... clicks only. For text, use `hdc shell aa start` with param? No.
// Practical path: hardware keyboard events via uinput -K (key events). '1','+','1' via keycodes then Enter.
// uinput -K -d 11 -u 11 style is for raw evdev. uitest keyEvent supports text?
// Try: uitest uiInput inputText? Check availability:
console.log(sh('uitest 2>&1 | head -5'));
