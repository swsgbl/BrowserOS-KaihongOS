#!/system/bin/sh
# P3 v10: sign + install + restart app (force stop for clean ability relaunch)
. /data/local/home/env.sh >/dev/null 2>&1
SIG="$OHOS_HOME/signature"
IN=/data/local/tmp/entry-api14-v10.hap
OUT=/data/local/tmp/browseros-v10-signed.hap
ls -l "$IN" || { echo NO_INPUT; exit 1; }
hap-sign-tool sign-app -keyAlias "OpenHarmony Application Release" -signAlg SHA256withECDSA -mode localSign -appCertFile "$SIG/OpenHarmonyApplication.pem" -profileFile "$SIG/browseros-profile-release.p7b" -inFile "$IN" -keystoreFile "$SIG/OpenHarmony.p12" -outFile "$OUT" -keyPwd 123456 -keystorePwd 123456 -compatibleVersion 14
ls -l "$OUT" || { echo SIGN_FAIL; exit 1; }
bm install -p "$OUT" -r
echo "== force stop =="
aa force-stop com.browseros.kaihong 2>&1 || true
sleep 1
echo "== relaunch =="
aa start -a EntryAbility -b com.browseros.kaihong
sleep 4
echo "== token file =="
ls -l /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/ 2>&1
echo "== token value =="
cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt 2>&1
echo DONE_P3_v10
