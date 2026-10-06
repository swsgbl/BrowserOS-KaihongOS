const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
execSync(`${HDC} -t ${T} shell "hilog -x > /data/local/tmp/p5_hilog.txt"`, { encoding: 'utf8', maxBuffer: 64e6 });
const out = execSync(`${HDC} -t ${T} shell "cat /data/local/tmp/p5_hilog.txt"`, { encoding: 'utf8', maxBuffer: 64e6 });
const kws = process.argv.slice(2);
const lines = out.split('\n').filter(l => l.indexOf('JSAPP') >= 0 || l.indexOf('AceContainer') >= 0 || l.indexOf('WebView') >= 0)
  .filter(l => kws.length === 0 || kws.some(k => l.indexOf(k) >= 0));
console.log('matched ' + lines.length);
console.log(lines.slice(-150).join('\n').replace(/.{400}/g, m => m.slice(0, 400)));
// truncate each line to 260 chars for readability
const short = lines.slice(-150).map(l => l.length > 300 ? l.slice(0, 300) + '…' : l);
console.log('---SHORT---');
console.log(short.join('\n'));
