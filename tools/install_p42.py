#!/usr/bin/env python3
"""P42 install: sign api23 hap on VM + bm install + relaunch (install_p8.py chain, api23 hap)."""
import os
import subprocess
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
TARGET = "192.168.161.137:10178"
HAP = os.path.join(PROJ, "entry-api23-unsigned.hap")
REMOTE = "/data/local/tmp/p42_entry.hap"
SIGN = ('/data/local/home/.local/bin/hap-sign-tool sign-app -keyAlias "OpenHarmony Application Release" '
        '-signAlg SHA256withECDSA -mode localSign '
        '-appCertFile /data/local/home/.ohos/signature/OpenHarmonyApplication.pem '
        '-profileFile /data/local/home/.ohos/signature/browseros-profile-release.p7b '
        f'-inFile {REMOTE} -outFile /data/local/tmp/p42_entry_signed.hap '
        '-keystoreFile /data/local/home/.ohos/signature/OpenHarmony.p12 '
        '-keyPwd 123456 -keystorePwd 123456 -compatibleVersion 23')


def hdc(*args):
    r = subprocess.run([HDC, "-t", TARGET] + list(args), capture_output=True, text=True)
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    print("> " + " ".join(args)[:110] + "\n   " + (out[-400:] if out else "(ok)"))
    return r.returncode, out


def main():
    if not os.path.exists(HAP):
        print("hap missing:", HAP)
        return 1
    hdc("shell", "rm -f /data/local/tmp/p42_entry_signed.hap")
    rc, _ = hdc("file", "send", HAP, REMOTE)
    if rc != 0:
        return 1
    rc, out = hdc("shell", SIGN)
    if "success" not in out.lower():
        print("SIGN FAILED")
        return 1
    rc, out = hdc("shell", "bm install -p /data/local/tmp/p42_entry_signed.hap -r")
    if "successfully" not in out.lower():
        print("INSTALL FAILED")
        return 1
    hdc("shell", "aa force-stop com.browseros.kaihong")
    rc, out = hdc("shell", "aa start -a EntryAbility -b com.browseros.kaihong")
    print("INSTALL+LAUNCH OK" if "successfully" in out.lower() else "LAUNCH FAILED")
    return 0 if "successfully" in out.lower() else 1


if __name__ == "__main__":
    sys.exit(main())
