"""P11: sync ic_*.svg into the V1 restool input dir + extend final_ids.json.
The V1 (KaihongOS 5.0 / API14 launcher) resources.index must contain the new
SVG media entries, else runtime $r('app.media.ic_*') fails -> blue boxes.
Runtime resolves $r() by NAME, so IDs just need to be unique; we reuse
hvigor's ids from id_defined.json for consistency.
"""
import json, os, shutil, glob

PROJ = r"D:\BrowserOS - KaihongOS"
MEDIA_IN = os.path.join(PROJ, "entry", "src", "main", "resources", "base", "media")
V1_FINAL_MEDIA = r"D:\v1tmp\final\resources\base\media"
IDS = r"D:\v1tmp\final_ids.json"
HVIGOR_IDS = os.path.join(PROJ, "entry", "build", "default", "intermediates",
                          "res", "default", "ids_map", "id_defined.json")

# 1. copy svgs
svgs = sorted(glob.glob(os.path.join(MEDIA_IN, "ic_*.svg")))
assert svgs, "no svg found in project media"
os.makedirs(V1_FINAL_MEDIA, exist_ok=True)
for p in svgs:
    shutil.copy2(p, V1_FINAL_MEDIA)
print("copied", len(svgs), "svgs ->", V1_FINAL_MEDIA)

# 2. extend ids
ids = json.load(open(IDS, encoding="utf-8"))
have = {r["name"] for r in ids["record"]}
hv = json.load(open(HVIGOR_IDS, encoding="utf-8"))
hvmap = {r["name"]: r["id"] for r in hv["record"] if r["type"] == "media"}
used = {int(r["id"], 16) for r in ids["record"]}
added = 0
for p in svgs:
    name = os.path.splitext(os.path.basename(p))[0]
    if name in have:
        continue
    nid = hvmap.get(name)
    if nid is None or int(nid, 16) in used:
        # fallback: next free id
        n = 0x0100000e
        while n in used:
            n += 1
        nid = "0x%08x" % n
    used.add(int(nid, 16))
    ids["record"].append({"id": nid, "type": "media", "name": name})
    added += 1
json.dump(ids, open(IDS, "w", encoding="utf-8"), indent=2)
print("ids added:", added, "total records:", len(ids["record"]))
