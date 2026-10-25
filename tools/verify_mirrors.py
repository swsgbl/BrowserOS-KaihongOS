#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P42-H: 镜像一致性校验 —— 本地 HEAD vs origin(GitHub) vs atomgit 三方比对。

用法: py tools/verify_mirrors.py [--proxy http://127.0.0.1:7892]
退出码: 0=三方一致 / 1=有分歧或远端不可达(如实报告)
"""
import argparse
import subprocess
import sys

REMOTE_KEYS = ["origin", "atomgit"]


def sh(cmd, timeout=40):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=timeout)
        return r.returncode, ((r.stdout or "") + (r.stderr or "")).strip()
    except Exception as e:
        return 1, str(e)


def remote_url(name):
    rc, out = sh(["git", "remote", "get-url", name])
    return out.strip() if rc == 0 else "?"


def ls_remote(name, proxy):
    cmd = ["git"]
    if proxy:
        cmd += ["-c", f"http.proxy={proxy}", "-c", "https.proxy={proxy}"]
    cmd += ["ls-remote", name, "HEAD"]
    rc, out = sh(cmd)
    if rc != 0 or not out:
        return None, out[:160]
    head = out.split()[0] if out.split() else ""
    return head, ""


def local_head():
    rc, out = sh(["git", "rev-parse", "HEAD"])
    return out.strip() if rc == 0 else "?"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--proxy", default=None)
    args = ap.parse_args()

    lh = local_head()
    print(f"local  HEAD: {lh}")

    heads = {}
    ok_all = True
    for name in REMOTE_KEYS:
        url = remote_url(name)
        head, err = ls_remote(name, args.proxy)
        if head is None:
            print(f"[UNREACHABLE] {name} ({url}) — {err}")
            ok_all = False
            continue
        heads[name] = head
        match = "==" if head == lh else "!="
        print(f"{name:8s} HEAD: {head} {match} local ({url})")
        if head != lh:
            ok_all = False

    if not heads:
        print("RESULT: no remote reachable (network?) — report as-is, do NOT fake success")
        return 1
    if ok_all:
        print("RESULT: all mirrors in sync with local HEAD")
        return 0
    print("RESULT: MISMATCH or partial unreachable — see above")
    return 1


if __name__ == "__main__":
    sys.exit(main())
