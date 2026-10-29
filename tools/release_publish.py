#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P69: release 发布侧工具 —— 生成/校验 update-manifest.json 并同步双仓。

仓库侧约定（与 service/UpdateService.ets 对齐）：
- manifest 放仓库根 update-manifest.json，双远端（GitHub + AtomGit）同步提交。
- AtomGit raw URL 实测形态: https://atomgit.com/<user>/<repo>/raw/<ref>/<path> (GET 200)
- sha256 必填；应用侧下载后强校验，不匹配拒装换源。

用法：
  python tools/release_publish.py --hap release/xxx.hap --tag v1.1.0 \
      [--notes "..."] [--manifest update-manifest.json]
  # 只校验已有 manifest: python tools/release_publish.py --check
"""
import argparse
import hashlib
import json
import os
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GH_REPO = "swsgbl/BrowserOS-KaihongOS"
CN_REPO = "hongfu/BrowserOS-KaihongOS"


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build_manifest(hap_path, tag, notes, min_api=23):
    name = os.path.basename(hap_path)
    gh_url = f"https://github.com/{GH_REPO}/releases/download/{tag}/{name}"
    cn_urls = [
        f"https://atomgit.com/{CN_REPO}/raw/main/release/{name}",
        f"https://ghfast.top/{gh_url}",
    ]
    # versionCode/Name 从 hap 内 module.json/app.json 读不到（app.json 在包内），从参数或现有 manifest 推
    return {
        "versionCode": None,  # 调用方必须提供 --version-code（或由 CI 注入）
        "versionName": tag.lstrip("v"),
        "sha256": sha256_of(hap_path),
        "size": os.path.getsize(hap_path),
        "notes": notes,
        "minCompatibleApi": min_api,
        "urls": {"global": [gh_url], "cn": cn_urls},
    }


def check_manifest(path):
    ok = True
    with open(path, encoding="utf-8") as f:
        m = json.load(f)
    for key in ("versionCode", "versionName", "sha256", "size", "urls"):
        if key not in m:
            print(f"[FAIL] manifest missing key: {key}")
            ok = False
    urls = m.get("urls", {})
    for region in ("global", "cn"):
        lst = urls.get(region)
        if not isinstance(lst, list) or not lst:
            print(f"[FAIL] urls.{region} must be a non-empty list")
            ok = False
        else:
            for u in lst:
                if not u.startswith("https://"):
                    print(f"[FAIL] urls.{region} non-https: {u}")
                    ok = False
    if m.get("sha256") and len(m["sha256"]) != 64:
        print("[FAIL] sha256 must be 64 hex chars")
        ok = False
    print("[PASS] manifest structure" if ok else "[FAIL] manifest structure")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hap")
    ap.add_argument("--tag")
    ap.add_argument("--notes", default="")
    ap.add_argument("--version-code", type=int)
    ap.add_argument("--manifest", default=os.path.join(PROJ, "update-manifest.json"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    if args.check:
        sys.exit(0 if check_manifest(args.manifest) else 1)

    if not args.hap or not args.tag or not args.version_code:
        ap.error("--hap --tag --version-code required (or --check)")

    m = build_manifest(args.hap, args.tag, args.notes)
    m["versionCode"] = args.version_code
    with open(args.manifest, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("wrote", args.manifest, "versionCode=", m["versionCode"], "size=", m["size"])
    print("sha256=", m["sha256"])
    print("release hap 应放入仓库 release/ 目录后双仓同步提交（GitHub release 附件 + AtomGit raw）")
    sys.exit(0 if check_manifest(args.manifest) else 1)


if __name__ == "__main__":
    main()
