"""P39->P40: produce an API23-compatible HAP from the SDK26 hvigor build, KEEPING the
RestoolV2 resources.index (direct-install for KaihongOS 6.x / API23).

The local DevEco only ships SDK 26, so compatibleSdkVersion in build-profile must
stay 26.0.0 (hvigor validates against installed SDKs); instead we patch
module.json/pack.info min/target API post-build.

P40 ROOT-CAUSE FIX (evidence/p40/): the previous repack used ZIP_DEFLATED for all
entries. KaihongOS 6.x (API23) resmgr/zip-reader can only fetch hap resource
entries that are STORED - deflated entries make every rawfile/media/id lookup
fail (rawfile err 9001005, drawable/string err 9001001) => ALL in-app icons
blank. hvigor's own product and every system hap on device are 100% STORED.
Fix: rewrite the zip with ZIP_STORED, preserving original entry order.
"""
import json
import os
import zipfile

PROJ = r"D:\BrowserOS - KaihongOS"
SRC_HAP = os.path.join(PROJ, "entry", "build", "default", "outputs", "default", "entry-default-unsigned.hap")
OUT_HAP = os.path.join(PROJ, "entry-api23-unsigned.hap")
API = 23

zsrc = zipfile.ZipFile(SRC_HAP)
mj = json.loads(zsrc.read("module.json"))
app = mj["app"]
app["minAPIVersion"] = API
app["targetAPIVersion"] = API
app["compileSdkVersion"] = "6.0.0"
app["compileSdkType"] = "HarmonyOS"

pi = json.loads(zsrc.read("pack.info"))
pi["summary"]["modules"][0]["apiVersion"]["compatible"] = API
pi["summary"]["modules"][0]["apiVersion"]["target"] = API

if os.path.exists(OUT_HAP):
    os.remove(OUT_HAP)
with zipfile.ZipFile(OUT_HAP, "w", zipfile.ZIP_STORED) as zf:
    for n in zsrc.namelist():
        if n == "module.json":
            data = json.dumps(mj, indent=2, ensure_ascii=False).encode("utf-8")
        elif n == "pack.info":
            data = json.dumps(pi, indent=2, ensure_ascii=False).encode("utf-8")
        else:
            data = zsrc.read(n)
        zf.writestr(n, data)

with zipfile.ZipFile(OUT_HAP) as zf:
    mj2 = json.load(zf.open("module.json"))
    idx = zf.read("resources.index")
    allstored = all(zi.compress_type == 0 for zi in zf.infolist())
    print("OUT:", OUT_HAP, os.path.getsize(OUT_HAP), "B")
    print("minAPI:", mj2["app"]["minAPIVersion"], "target:", mj2["app"]["targetAPIVersion"],
          "index head:", idx[:17], "all-STORED:", allstored)
    assert allstored, "repack must be all-STORED for KaihongOS resmgr"
