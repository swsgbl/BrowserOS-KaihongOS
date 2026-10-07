"""P8 build-chain V1 index pipeline (definitive).

From the freshly built hvigor hap, produce a HAP whose resources.index header is
Restool 5.0.x (V1) - required by the KaihongOS 5.0 (API14) launcher - instead of
RestoolV2 produced by DevEco SDK 26.

Verified facts (hmh, 2026-10-07):
  restool 5.0.1 (D:\\OHOS-QEMU\\sdk-5.0.2\\14) input layout must be
      <in>/resources/base/...   (+ <in>/module.json with SYMBOLIC $refs)
  -o dir must pre-exist; --defined-ids ids are hex strings "0x01000001".
  Output module.json keeps symbolic refs, so we digitize ourselves with the
  fixed id map that matches the compiled index.
"""
import json, os, shutil, subprocess, zipfile

PROJ = r"D:\BrowserOS - KaihongOS"
RESTOOL = r"D:\OHOS-QEMU\sdk-5.0.2\14\toolchains\restool.exe"
V1 = r"D:\v1tmp"
SRC_HAP = os.path.join(PROJ, "entry", "build", "default", "outputs", "default", "entry-default-unsigned.hap")
OUT_HAP = os.path.join(PROJ, "entry-p8-v1-unsigned.hap")
WORK = os.path.join(V1, "p8final")

# ---------- 1. restool V1 compile (resources -> index) ----------
IN = os.path.join(V1, "final")          # built by build_final_v1.py (resources/base + module.json)
OUTRESTOOL = os.path.join(V1, "finalout")
r = subprocess.run([RESTOOL, "-i", IN, "-p", "entry", "-o", OUTRESTOOL, "-f",
                    "-r", os.path.join(V1, "ResourceTable.js"),
                    "--ids", OUTRESTOOL, "--defined-ids", os.path.join(V1, "final_ids.json")],
                   capture_output=True, text=True)
assert r.returncode == 0, r.stderr[-500:]
v1_index = open(os.path.join(OUTRESTOOL, "resources.index"), "rb").read()
assert v1_index[:8] == b"Restool ", v1_index[:20]
print("V1 index:", len(v1_index), "B head:", v1_index[:17])

# id map (must match final_ids.json / the compiled index)
ID = {
    "app_name": 0x01000001, "EntryAbility_label": 0x01000002,
    "EntryAbility_desc": 0x01000003, "module_desc": 0x01000004,
    "internet_permission_reason": 0x01000005, "file_access_permission_reason": 0x01000006,
    "storage_permission_reason": 0x01000007, "start_window_background": 0x01000008,
    "app_icon": 0x01000009, "app_icon_48": 0x0100000a, "app_icon_96": 0x0100000b,
    "app_icon_192": 0x0100000c, "app_icon_216": 0x0100000d,
}
# NOTE: the old (device-verified) hap keeps SYMBOLIC refs in module.json with the
# numeric *Id fields as parallel cache; BMS 9568342 "parse profile prop type error"
# happens when refs are replaced by ints (app.icon must stay "$media:...").

# ---------- 2. unpack fresh hvigor hap ----------
if os.path.exists(WORK):
    shutil.rmtree(WORK)
os.makedirs(WORK)
with zipfile.ZipFile(SRC_HAP) as zf:
    zf.extractall(WORK)

# ---------- 3. swap resources.index ----------
old = open(os.path.join(WORK, "resources.index"), "rb").read()
print("old index head:", old[:17], len(old), "B")
with open(os.path.join(WORK, "resources.index"), "wb") as f:
    f.write(v1_index)

# ---------- 4. module.json: API14 + digitized resource refs ----------
mp = os.path.join(WORK, "module.json")
mj = json.load(open(mp, encoding="utf-8"))
app = mj["app"]
app["minAPIVersion"] = 14
app["targetAPIVersion"] = 14
app["compileSdkVersion"] = "14"
app["compileSdkType"] = "OpenHarmony"
app["label"] = "$string:app_name"
app["labelId"] = ID["app_name"]
app["icon"] = "$media:app_icon"
app["iconId"] = ID["app_icon"]
for ab in mj["module"].get("abilities", []):
    ab["label"] = "$string:EntryAbility_label"
    ab["labelId"] = ID["EntryAbility_label"]
    ab["description"] = "$string:EntryAbility_desc"
    ab["descriptionId"] = ID["EntryAbility_desc"]
    ab["icon"] = "$media:app_icon"
    ab["iconId"] = ID["app_icon"]
    ab["startWindowIcon"] = "$media:app_icon"
    ab["startWindowIconId"] = ID["app_icon"]
    ab["startWindowBackground"] = "$color:start_window_background"
    ab["startWindowBackgroundId"] = ID["start_window_background"]
for perm in mj["module"].get("requestPermissions", []):
    if "reason" in perm:
        perm["reason"] = "$string:internet_permission_reason"
        perm["reasonId"] = ID["internet_permission_reason"]
json.dump(mj, open(mp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)

# ---------- 5. pack.info -> API14 ----------
pp = os.path.join(WORK, "pack.info")
pi = json.load(open(pp, encoding="utf-8"))
pi["summary"]["modules"][0]["apiVersion"]["compatible"] = 14
pi["summary"]["modules"][0]["apiVersion"]["target"] = 14
json.dump(pi, open(pp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)

# ---------- 6. multi-size icons already in resources/ (from hvigor build) - verify ----------
names = zipfile.ZipFile(SRC_HAP).namelist()
for want in ["resources/base/media/app_icon.png", "resources/base/media/app_icon_96.png",
             "resources/base/media/app_icon_192.png", "resources/base/media/app_icon_216.png"]:
    print(("OK  " if want in names else "MISS"), want)

# ---------- 7. repack ----------
if os.path.exists(OUT_HAP):
    os.remove(OUT_HAP)
order = ["ets/modules.abc", "ets/sourceMaps.map", "module.json", "pack.info",
         "resources.index"]
with zipfile.ZipFile(OUT_HAP, "w", zipfile.ZIP_DEFLATED) as zf:
    written = set()
    for name in order:
        p = os.path.join(WORK, name)
        if os.path.exists(p):
            zf.write(p, name)
            written.add(name)
    for root, dirs, files in os.walk(WORK):
        for fn in files:
            p = os.path.join(root, fn)
            arc = os.path.relpath(p, WORK).replace("\\", "/")
            if arc not in written:
                zf.write(p, arc)
                written.add(arc)

print("OUT:", OUT_HAP, os.path.getsize(OUT_HAP), "B")
with zipfile.ZipFile(OUT_HAP) as zf:
    idx = zf.read("resources.index")
    print("packed index head:", idx[:17])
    mj2 = json.load(zf.open("module.json"))
    print("app.icon:", mj2["app"]["icon"], "label:", mj2["app"]["label"],
          "minAPI:", mj2["app"]["minAPIVersion"], "bundle:", mj2["app"]["bundleName"])
