"""P11: force-align ALL media ids in D:\\v1tmp\\final_ids.json to hvigor's
id_defined.json (name -> id, only when free). Fixes drift where alphabetical
insertion of new svgs renumbers png ids in hvigor but final_ids.json keeps
stale ids -> runtime $r() resolves to wrong entries (broken icons).
"""
import json, os

IDS = r"D:\v1tmp\final_ids.json"
HVIGOR_IDS = os.path.join(r"D:\BrowserOS - KaihongOS", "entry", "build", "default",
                          "intermediates", "res", "default", "ids_map", "id_defined.json")

ids = json.load(open(IDS, encoding="utf-8"))
hv = json.load(open(HVIGOR_IDS, encoding="utf-8"))
hvmap = {r["name"]: r["id"] for r in hv["record"] if r["type"] == "media"}

fixed = 0
for r in ids["record"]:
    want = hvmap.get(r["name"])
    if want and r["id"] != want:
        old = r["id"]
        r["id"] = want
        fixed += 1
        print(f"align {r['name']}: {old} -> {want}")

# uniqueness check within same type (hvigor ids are unique per-type only;
# a media id may numerically equal a string id - restool indexes by type+id)
seen = {}
for r in ids["record"]:
    k = r["type"] + ":" + r["id"]
    if k in seen:
        raise SystemExit(f"DUPLICATE id after align: {r['id']} {r['name']} vs {seen[k]}")
    seen[k] = r["name"]

json.dump(ids, open(IDS, "w", encoding="utf-8"), indent=2)
print(f"aligned {fixed} ids, total {len(ids['record'])} records, all unique")
