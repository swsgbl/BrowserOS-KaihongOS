#!/system/bin/sh
# p63: sign + install + relaunch
. /data/local/home/env.sh >/dev/null 2>&1
SIG="$OHOS_HOME/signature"
IN=/data/local/tmp/p63-entry.hap
OUT=/data/local/tmp/p63-signed.hap
ls -l "$IN" || { echo NO_INPUT; exit 1; }
hap-sign-tool sign-app -keyAlias "OpenHarmony Application Release" -signAlg SHA256withECDSA -mode localSign -appCertFile "$SIG/OpenHarmonyApplication.pem" -profileFile "$SIG/browseros-profile-release.p7b" -inFile "$IN" -keystoreFile "$SIG/OpenHarmony.p12" -outFile "$OUT" -keyPwd 123456 -keystorePwd 123456 -compatibleVersion 23
ls -l "$OUT" || { echo SIGN_FAIL; exit 1; }
bm install -p "$OUT" -r
aa force-stop com.browseros.kaihong 2>&1 || true
sleep 1
aa start -a EntryAbility -b com.browseros.kaihong
sleep 4
echo DONE_p63
