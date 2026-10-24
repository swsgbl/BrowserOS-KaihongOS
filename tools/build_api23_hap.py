"""P39: produce an API23-compatible HAP from the SDK26 hvigor build, KEEPING the
RestoolV2 resources.index (direct-install experiment for KaihongOS 6.x / API23).

The local DevEco only ships SDK 26, so compatibleSdkVersion in build-profile must
stay 26.0.0 (hvigor validates against installed SDKs); instead we patch
module.json/pack.info min/target API post-build — same digitizing trick the V1
repack always did for API14, minus the restool step.
"""
import json
import os
import shutil
import zipfile

PROJ = r"D:\BrowserOS - KaihongOS"
SRC_HAP = os.path.join(PROJ, "entry", "build", "default", "outputs", "default", "entry-default-unsigned.hap")
OUT_HAP = os.path.join(PROJ, "entry-api23-unsigned.hap")
WORK = os.path.join(PROJ, "attic", "api23work")
API = 23

if os.path.exists(WORK):
    shutil.rmtree(WORK)
os.makedirs(WORK)
with zipfile.ZipFile(SRC_HAP) as zf:
    zf.extractall(WORK)

mp = os.path.join(WORK, "module.json")
mj = json.load(open(mp, encoding="utf-8"))
app = mj["app"]
app["minAPIVersion"] = API
app["targetAPIVersion"] = API
app["compileSdkVersion"] = "6.0.0"
app["compileSdkType"] = "HarmonyOS"
json.dump(mj, open(mp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)

pp = os.path.join(WORK, "pack.info")
pi = json.load(open(pp, encoding="utf-8"))
av = pi["summary"]["modules"][0]["apiVersion"]
av["compatible"] = API
av["target"] = API
json.dump(pi, open(pp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)

if os.path.exists(OUT_HAP):
    os.remove(OUT_HAP)
order = ["ets/modules.abc", "ets/sourceMaps.map", "module.json", "pack.info", "resources.index"]
with zipfile.ZipFile(OUT_HAP, "w", zipfile.ZIP_DEFLATED) as zf:
    written = set()
    for name in order:
        p = os.path.join(WORK, name)
        if os.path.exists(p):
            zf.write(p, name)
            written.add(name)
    for root, _, files in os.walk(WORK):
        for fn in files:
            p = os.path.join(root, fn)
            arc = os.path.relpath(p, WORK).replace("\\", "/")
            if arc not in written:
                zf.write(p, arc)
                written.add(arc)

with zipfile.ZipFile(OUT_HAP) as zf:
    mj2 = json.load(zf.open("module.json"))
    idx = zf.read("resources.index")
    print("OUT:", OUT_HAP, os.path.getsize(OUT_HAP), "B")
    print("minAPI:", mj2["app"]["minAPIVersion"], "targetAPI:", mj2["app"]["targetAPIVersion"],
          "index head:", idx[:17])
