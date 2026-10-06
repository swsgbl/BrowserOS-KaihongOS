const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe" -t 127.0.0.1:15566 shell ';
function sh(cmd) { return execSync(HDC + '"' + cmd + '"', { encoding: 'utf8', timeout: 30000 }); }

// session files
console.log('--- sessions dir ---');
console.log(sh('find /data/app/el2/100/base/com.browseros.kaihong -name "*.json" -path "*session*" 2>/dev/null'));
console.log(sh('find /data/app/el2/100/base/com.browseros.kaihong -type d 2>/dev/null | head -20'));
