"""P40-A: push + VM-sign + install + launch + hilog verify the STORED-repack hypothesis.
If icons render => root cause = DEFLATE compression breaking KaihongOS resmgr zip reader."""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p40"
HAP = r"D:\BrowserOS - KaihongOS\entry-api23-stored-unsigned.hap"

def sh(c, tmo=120):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

# 1. push
r = subprocess.run([HDC, '-t', T, 'file', 'send', HAP, '/data/local/tmp/x.hap'], capture_output=True, text=True, timeout=180, encoding='utf-8', errors='replace')
print('send:', (r.stdout or r.stderr).strip())

# 2. VM sign (P39 chain)
SIGN = ("/data/local/home/.local/bin/hap-sign-tool sign-app -keyAlias 'OpenHarmony Application Release' "
        "-signAlg SHA256withECDSA -mode localSign "
        "-appCertFile /data/local/home/.ohos/signature/OpenHarmonyApplication.pem "
        "-profileFile /data/local/home/.ohos/signature/browseros-profile-release.p7b "
        "-inFile /data/local/tmp/x.hap -outFile /data/local/tmp/x_signed.hap "
        "-keystoreFile /data/local/home/.ohos/signature/OpenHarmony.p12 -keyPwd 123456 -keystorePwd 123456 -compatibleVersion 23")
print('sign:', sh(SIGN, tmo=120)[-300:])

# 3. install
print('install:', sh('bm install -p /data/local/tmp/x_signed.hap -r', tmo=120)[-400:])
