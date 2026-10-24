#!/usr/bin/env python3
"""BrowserOS KaihongOS - One-command build & deploy
Usage: python tools/deploy.py [--skip-shortcut]

Steps:
  1. hvigorw assembleHap (build from source)
  2. restool V1 repack (API 14 compatible resources.index)
  3. Sign on device (hap-sign-tool)
  4. Install (bm install -r)
  5. Desktop shortcut (optional)
"""
import subprocess, sys, os, time

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
BUNDLE = "com.browseros.kaihong"
TARGET = "192.168.161.137:10178"

def run(cmd, cwd=BASE, desc=""):
    print(f"[{desc}] {cmd[:80]}...")
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd)
    if r.returncode != 0:
        print(f"  FAIL: {r.stderr[:200]}")
        return False
    if r.stdout.strip():
        print(f"  {r.stdout.strip()[:120]}")
    return True

def hdc(cmd, desc=""):
    return run(f'"{HDC}" shell "{cmd}"', desc=desc)

def main():
    skip_shortcut = "--skip-shortcut" in sys.argv
    print("=" * 50)
    print("BrowserOS KaihongOS - Build & Deploy")
    print("=" * 50)

    # Step 1: Build
    if not run("hvigorw assembleHap --mode module -p product=default --no-daemon",
               desc="BUILD"):
        sys.exit(1)

    # Step 2: V1 repack
    if not run("python tools/build_v1_hap.py", desc="V1 REPACK"):
        sys.exit(1)

    # Step 3: Push to device
    hap = os.path.join(BASE, "entry-p8-v1-unsigned.hap")
    if not run(f'"{HDC}" file send "{hap}" /data/local/tmp/deploy.hap', desc="PUSH"):
        sys.exit(1)

    # Step 4: Sign on device
    sign = (
        "/data/local/home/.local/bin/hap-sign-tool sign-app "
        "-keyAlias 'OpenHarmony Application Release' "
        "-signAlg SHA256withECDSA -mode localSign "
        "-appCertFile /data/local/home/.ohos/signature/OpenHarmonyApplication.pem "
        "-profileFile /data/local/home/.ohos/signature/browseros-profile-release.p7b "
        "-inFile /data/local/tmp/deploy.hap "
        "-outFile /data/local/tmp/deploy-signed.hap "
        "-keystoreFile /data/local/home/.ohos/signature/OpenHarmony.p12 "
        "-keyPwd 123456 -keystorePwd 123456 -compatibleVersion 14"
    )
    if not hdc(sign, desc="SIGN"):
        sys.exit(1)

    # Step 5: Install
    if not hdc(f"bm install -p /data/local/tmp/deploy-signed.hap -r", desc="INSTALL"):
        sys.exit(1)

    # Step 6: Launch
    hdc(f"aa start -a EntryAbility -b {BUNDLE}", desc="LAUNCH")

    # Step 7: Desktop shortcut (optional)
    if not skip_shortcut:
        run("python tools/add_desktop_shortcut.py", desc="SHORTCUT")

    print("\n" + "=" * 50)
    print("DEPLOY COMPLETE")
    print("=" * 50)

if __name__ == "__main__":
    main()
