#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P69 验收辅助：本地 HTTP 源 + 假 manifest 制造机。

目录 evidence/p69/www/:
  update-manifest.json   —— versionCode+1、指向本机两个"源"URL
  cn/browseros-1.1.1.hap —— "国内源"包（真 hap）
  global/browseros-1.1.1.hap —— "国际源"包
"""
import hashlib
import json
import os
import shutil

PROJ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WWW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "www")
HAP = os.path.join(PROJ, "entry-api23-unsigned.hap")


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build(ver_name="1.1.1", ver_code=1010001, tamper_sha=False, cn_only=False, global_only=False,
          cn_bad=False):
    os.makedirs(os.path.join(WWW, "cn"), exist_ok=True)
    os.makedirs(os.path.join(WWW, "global"), exist_ok=True)
    fname = f"browseros-{ver_name}.hap"
    cn_hap = os.path.join(WWW, "cn", fname)
    gl_hap = os.path.join(WWW, "global", fname)
    shutil.copyfile(HAP, cn_hap)
    shutil.copyfile(HAP, gl_hap)
    sha = sha256_of(cn_hap)
    sha_field = ("0" * 64) if tamper_sha else sha
    urls_cn = [f"http://192.168.161.1:8931/cn/{fname}"]
    urls_global = [f"http://192.168.161.1:8931/global/{fname}"]
    if cn_bad:
        # 第一个 cn URL 指向不存在的路径（制造 cn 源失败 → 换源）
        urls_cn = [f"http://192.168.161.1:8931/cn/missing.hap"] + urls_cn
    if cn_only:
        urls_global = []
    if global_only:
        urls_cn = []
    m = {
        "versionCode": ver_code,
        "versionName": ver_name,
        "sha256": sha_field,
        "size": os.path.getsize(cn_hap),
        "notes": "P69 验收假版本（e2e）",
        "minCompatibleApi": 23,
        "urls": {"global": urls_global, "cn": urls_cn},
    }
    with open(os.path.join(WWW, "update-manifest.json"), "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=2)
    print("manifest built:")
    print(json.dumps(m, ensure_ascii=False, indent=1))
    return m


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="normal",
                    choices=["normal", "tamper", "cnbad", "cnonly", "globalonly"])
    a = ap.parse_args()
    kw = {"normal": {}, "tamper": {"tamper_sha": True}, "cnbad": {"cn_bad": True},
          "cnonly": {"cn_only": True}, "globalonly": {"global_only": True}}[a.mode]
    build(**kw)
