const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
const out = execSync(`${HDC} -t ${T} shell "cat /data/local/tmp/p5_h2.txt"`, { encoding: 'utf8', maxBuffer: 64e6 });
// find newest pid with JSAPP BrowserShell-ish lines
const map = {};
out.split('\n').forEach(l => {
  const m = l.match(/^\d+-\d+ (\d\d:\d\d:\d\d\.\d+)\s+(\d+)\s+\d+ I A03d00\/JSAPP: (.*)$/);
  if (m && /BrowserShell|EntryAbility|NeoDash|rebuild/.test(m[3])) {
    if (!map[m[2]]) map[m[2]] = [];
    map[m[2]].push(m[1] + ' ' + m[3].slice(0, 130));
  }
});
Object.keys(map).forEach(pid => {
  console.log('--- pid ' + pid + ' (' + map[pid].length + ') ---');
  map[pid].slice(-12).forEach(x => console.log(x));
});
