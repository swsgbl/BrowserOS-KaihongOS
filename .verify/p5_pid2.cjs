const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
execSync(`${HDC} -t ${T} shell "hilog -x > /data/local/tmp/p5_h2.txt"`, { encoding: 'utf8', maxBuffer: 64e6 });
const out = execSync(`${HDC} -t ${T} shell "cat /data/local/tmp/p5_h2.txt"`, { encoding: 'utf8', maxBuffer: 64e6 });
const ls = out.split('\n').filter(l => l.indexOf('JSAPP') >= 0 && (l.indexOf('BrowserShell') >= 0 || l.indexOf('EntryAbility') >= 0));
console.log('n=' + ls.length);
console.log(ls.slice(-30).map(l => l.length > 240 ? l.slice(0, 240) : l).join('\n'));
