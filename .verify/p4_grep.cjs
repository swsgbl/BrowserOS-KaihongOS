const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe" -t 127.0.0.1:15566 shell ';
function sh(cmd) { return execSync(HDC + '"' + cmd + '"', { encoding: 'utf8', timeout: 30000 }); }

const raw = sh('tail -1500 /data/local/tmp/p4_log.txt');
const lines = raw.split('\n').filter(l => /SessionManager|AgentEngine/.test(l));
console.log('total matched: ' + lines.length);
console.log(lines.slice(-60).join('\n'));
