const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
function run(label, cmd) {
  console.log('=== ' + label + ' ===');
  const out = execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
  console.log(out.trim());
  return out;
}
// 1. send
console.log(execSync(`${HDC} -t ${T} file send ".verify\\p4_repack\\entry-p4-api14.hap" /data/local/tmp/entry-p5.hap`, { encoding: 'utf8' }).trim());
// 2. sign
run('sign', "/data/local/home/.local/bin/hap-sign-tool sign-app -keyAlias 'OpenHarmony Application Release' -signAlg SHA256withECDSA -mode localSign -appCertFile /data/local/home/.ohos/signature/OpenHarmonyApplication.pem -profileFile /data/local/home/.ohos/signature/browseros-profile-release.p7b -inFile /data/local/tmp/entry-p5.hap -outFile /data/local/tmp/entry-p5-signed.hap -keystoreFile /data/local/home/.ohos/signature/OpenHarmony.p12 -keyPwd 123456 -keystorePwd 123456 -compatibleVersion 14");
// 3. install + restart
run('install+restart', 'bm install -p /data/local/tmp/entry-p5-signed.hap -r; aa force-stop com.browseros.kaihong; sleep 1; aa start -a EntryAbility -b com.browseros.kaihong');
