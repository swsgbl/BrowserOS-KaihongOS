const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
execSync(`${HDC} -t ${T} shell "hilog -x > /data/local/tmp/p5_h3.txt"`, { encoding: 'utf8', maxBuffer: 64e6 });
const out = execSync(`${HDC} -t ${T} shell "cat /data/local/tmp/p5_h3.txt"`, { encoding: 'utf8', maxBuffer: 64e6 });
const ls = out.split('\n').filter(l => l.indexOf('JSAPP') >= 0 && /attach|bindWebView|BCP|navigate|onPageEnd|WebView|screenshot|AgentEngine|registerWebView|title|COMPLETED|complete/i.test(l))
  .map(l => l.length > 230 ? l.slice(0, 230) : l);
console.log('n=' + ls.length);
console.log(ls.slice(-60).join('\n'));
