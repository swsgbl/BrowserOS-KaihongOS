const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe" -t 127.0.0.1:15566 shell ';
function sh(cmd) { return execSync(HDC + '"' + cmd + '"', { encoding: 'utf8', timeout: 30000 }); }

sh("hilog -x > /data/local/tmp/p4_log2.txt 2>&1");
const raw = sh('tail -3000 /data/local/tmp/p4_log2.txt');
const lines = raw.split('\n').filter(l => /AgentEngine|SessionManager|BCP|task/.test(l) && !/capture failed/.test(l));
console.log('matched: ' + lines.length);
console.log(lines.slice(-45).join('\n'));
