const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe" -t 127.0.0.1:15566 shell ';
function sh(cmd) { return execSync(HDC + '"' + cmd + '"', { encoding: 'utf8', timeout: 30000 }); }

const raw = sh('tail -3000 /data/local/tmp/p4_log3.txt');
const lines = raw.split('\n').filter(l => /SessionManager|SessionPlayer/.test(l));
console.log('matched: ' + lines.length);
console.log(lines.slice(-30).join('\n'));
console.log('--- second session json ---');
const j = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/sessions/ses_1791261403052_yqdhztcb.json');
const o = JSON.parse(j);
console.log('sessionId=' + o.sessionId + ' agent=' + o.agentId);
console.log('operationLogs=' + o.operationLogs.length + ' screenshots=' + o.screenshots.length + ' urlSequence=' + o.urlSequence.length);
if (o.screenshots.length > 0) {
  const s = o.screenshots[0];
  console.log('shot0: keys=' + Object.keys(s).join(',') + ' dataPrefix=' + (s.data ? s.data.substring(0, 30) : 'none') + ' url=' + (s.url || ''));
}
