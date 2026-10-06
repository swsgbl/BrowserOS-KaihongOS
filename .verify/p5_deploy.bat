@echo off
rem P5 deploy pipeline: send -> sign -> install -> restart (build+repack must run first)
set HDC=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe
%HDC% -t 127.0.0.1:15566 file send ".verify\p4_repack\entry-p4-api14.hap" /data/local/tmp/entry-p5.hap || exit /b 1
%HDC% -t 127.0.0.1:15566 shell "/data/local/home/.local/bin/hap-sign-tool sign-app -keyAlias 'OpenHarmony Application Release' -signAlg SHA256withECDSA -mode localSign -appCertFile /data/local/home/.ohos/signature/OpenHarmonyApplication.pem -profileFile /data/local/home/.ohos/signature/browseros-profile-release.p7b -inFile /data/local/tmp/entry-p5.hap -outFile /data/local/tmp/entry-p5-signed.hap -keystoreFile /data/local/home/.ohos/signature/OpenHarmony.p12 -keyPwd 123456 -keystorePwd 123456 -compatibleVersion 14" || exit /b 1
%HDC% -t 127.0.0.1:15566 shell "bm install -p /data/local/tmp/entry-p5-signed.hap -r; aa force-stop com.browseros.kaihong; sleep 1; aa start -a EntryAbility -b com.browseros.kaihong"
