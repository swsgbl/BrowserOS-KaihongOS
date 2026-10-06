const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
const out = execSync(`${HDC} -t ${T} shell "hilog -x"`, { encoding: 'utf8', maxBuffer: 40 * 1024 * 1024 });
const lines = out.split('\n').filter(l => l.includes('29304'));
// window: 13:23:40 - 13:24:07 (NeoDashboard visit in second run)
const inWin = lines.filter(l => {
  const m = l.match(/10-06 (\d\d):(\d\d):(\d\d)/);
  if (!m) return false;
  const t = parseInt(m[1]) * 3600 + parseInt(m[2]) * 60 + parseInt(m[3]);
  return t >= 13 * 3600 + 23 * 60 + 40 && t <= 13 * 3600 + 24 * 60 + 7;
});
console.log(inWin.join('\n'));
console.log('[lines in window: ' + inWin.length + ']');
