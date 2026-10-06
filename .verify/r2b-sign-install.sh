#!/system/bin/sh
# bundle-rename relay2: sign app with NEW profile + install
. /data/local/home/env.sh >/dev/null 2>&1
SIG="$OHOS_HOME/signature"
IN=/data/local/tmp/entry-api14-v6.hap
OUT=/data/local/tmp/browseros-signed.hap
ls -l "$IN" || { echo NO_INPUT; exit 1; }
hap-sign-tool sign-app -keyAlias "OpenHarmony Application Release" -signAlg SHA256withECDSA -mode localSign -appCertFile "$SIG/OpenHarmonyApplication.pem" -profileFile "$SIG/browseros-profile-release.p7b" -inFile "$IN" -keystoreFile "$SIG/OpenHarmony.p12" -outFile "$OUT" -keyPwd 123456 -keystorePwd 123456 -compatibleVersion 14
ls -l "$OUT" || { echo SIGN_FAIL; exit 1; }
bm install -p "$OUT" -r
echo DONE_RELAY2_SIGN_INSTALL
