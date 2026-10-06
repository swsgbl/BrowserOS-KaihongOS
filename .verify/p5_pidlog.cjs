const { execSync } = require('child_process');
const fs = require('fs');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
const pid = process.argv[2];
const filter = process.argv[3] || '';
const t0 = process.argv[4]; // "HH:MM:SS"
const t1 = process.argv[5];
const out = execSync(`${HDC} -t ${T} shell "hilog -x"`, { encoding: 'utf8', maxBuffer: 40 * 1024 * 1024 });
let lines = out.split('\n').filter(l => pid ? l.includes(' ' + pid + ' ') : true);
if (filter) {
  const re = new RegExp(filter, 'i');
  lines = lines.filter(l => re.test(l));
}
function sec(l) {
  const m = l.match(/10-06 (\d\d):(\d\d):(\d\d)/);
  return m ? parseInt(m[1]) * 3600 + parseInt(m[2]) * 60 + parseInt(m[3]) : -1;
}
if (t0) lines = lines.filter(l => { const t = sec(l); return t >= 0 && t >= toSec(t0) && t <= toSec(t1); });
function toSec(s) { const p = s.split(':'); return parseInt(p[0]) * 3600 + parseInt(p[1]) * 60 + parseInt(p[2]); }
console.log(lines.slice(-100).join('\n'));
console.log('[matched ' + lines.length + ']');
