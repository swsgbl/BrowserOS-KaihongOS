const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe" -t 127.0.0.1:15566 shell ';
function sh(cmd) { return execSync(HDC + '"' + cmd + '"', { encoding: 'utf8', timeout: 30000 }); }
const raw = sh('grep JSAPP /data/local/tmp/p4_log3.txt | grep -i "session\\|agent" | tail -25');
console.log(raw);
