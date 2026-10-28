"""P60: push notification-fix hap to VM + sign + bm install + relaunch."""
import subprocess

HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
TARGET = "192.168.161.137:10178"
HAP = r"D:\BrowserOS - KaihongOS\entry-api23-unsigned.hap"
REMOTE = "/data/local/tmp/p60_entry.hap"
SIGN = ('/data/local/home/.local/bin/hap-sign-tool sign-app -keyAlias "OpenHarmony Application Release" '
        '-signAlg SHA256withECDSA -mode localSign '
        '-appCertFile /data/local/home/.ohos/signature/OpenHarmonyApplication.pem '
        '-profileFile /data/local/home/.ohos/signature/browseros-profile-release.p7b '
        '-inFile /data/local/tmp/p60_entry.hap -outFile /data/local/tmp/p60_entry_signed.hap '
        '-keystoreFile /data/local/home/.ohos/signature/OpenHarmony.p12 '
        '-keyPwd 123456 -keystorePwd 123456 -compatibleVersion 23')


def hdc(*args):
    r = subprocess.run([HDC, "-t", TARGET] + list(args), capture_output=True, text=True)
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    print(">", " ".join(args)[:100], "\n  ", out[-400:] if out else "(ok)")
    return r.returncode, out


hdc("shell", "rm -f " + REMOTE + " /data/local/tmp/p60_entry_signed.hap")
rc, _ = hdc("file", "send", HAP, REMOTE)
assert rc == 0, "file send failed"
rc, out = hdc("shell", "ls -l " + REMOTE)
assert "p60_entry.hap" in out, "remote hap missing"
rc, out = hdc("shell", SIGN)
assert "success" in out.lower(), out
rc, out = hdc("shell", "bm install -p /data/local/tmp/p60_entry_signed.hap -r")
assert "successfully" in out.lower(), out
hdc("shell", "aa force-stop com.browseros.kaihong")
rc, out = hdc("shell", "aa start -a EntryAbility -b com.browseros.kaihong")
print("P60 INSTALL+LAUNCH rc =", rc)
print(out)
