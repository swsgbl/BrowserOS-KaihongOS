const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe" -t 127.0.0.1:15566 shell ';

function sh(cmd) {
  return execSync(HDC + '"' + cmd + '"', { encoding: 'utf8', timeout: 20000 });
}

console.log('--- files dir ---');
console.log(sh('ls -la /data/app/el2/100/base/com.browseros.kaihong/files/'));
console.log('--- token ---');
console.log(sh('cat /data/app/el2/100/base/com.browseros.kaihong/files/mcp_token.txt'));
