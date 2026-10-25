#!/usr/bin/env python3
"""Offline static test suite — CI gate (no device/SDK needed).

Checks:
  1. tools/*.py compile clean (py_compile)
  2. entry/src/main/ets has no console.log( (project convention: console.info)
  3. entry/src/main/module.json5 exists and declares the expected ability
  4. Repo must-have files present (LICENSE / README.md / DEVPLAN.md / docs)
  5. SVG icon set non-empty under entry resources
Exit code 0 = all pass; 1 = failures listed on stderr.
"""
import py_compile
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ETS = ROOT / "entry" / "src" / "main" / "ets"

failures = []
notes = []


def check(name, ok, detail=""):
    tag = "PASS" if ok else "FAIL"
    print(f"[{tag}] {name}" + (f" - {detail}" if detail else ""))
    if not ok:
        failures.append(name)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    # 1. tools compile
    for py in sorted((ROOT / "tools").glob("*.py")):
        try:
            py_compile.compile(str(py), doraise=True)
            ok = True
            detail = ""
        except py_compile.PyCompileError as e:
            ok = False
            detail = str(e).splitlines()[-1] if str(e) else "compile error"
        check(f"py_compile {py.name}", ok, detail)

    # 2. console.log ban in ArkTS
    offenders = []
    icon_offenders = []
    for ets in ETS.rglob("*.ets"):
        try:
            text = ets.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            offenders.append(f"{ets.name}: unreadable {e}")
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if "console.log(" in line:
                offenders.append(f"{ets.relative_to(ROOT)}:{i}")
            # P38: icons must load via $rawfile (id-drift immune), never $r media
            if "$r('app.media.ic_" in line:
                icon_offenders.append(f"{ets.relative_to(ROOT)}:{i}")
    check("no console.log( in ArkTS (use console.info)", not offenders,
          "; ".join(offenders[:5]))
    check("icons via $rawfile not $r media (P38)", not icon_offenders,
          "; ".join(icon_offenders[:5]))

    # 3. module.json5 sanity
    mj = ROOT / "entry" / "src" / "main" / "module.json5"
    if mj.exists():
        text = mj.read_text(encoding="utf-8", errors="replace")
        check("module.json5 declares EntryAbility",
              "EntryAbility" in text and "abilities" in text)
    else:
        check("module.json5 exists", False, str(mj))

    # 4. repo must-have files（P41 合规套件）
    for rel in ("LICENSE", "NOTICE", "README.md", "DEVPLAN.md", "CHANGELOG.md",
                "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SECURITY.md",
                "docs/ARCHITECTURE.md", ".github/ISSUE_TEMPLATE/bug_report.md",
                ".github/PULL_REQUEST_TEMPLATE.md"):
        check(f"file {rel}", (ROOT / rel).exists())

    # 5. icon set
    media = ROOT / "entry" / "src" / "main" / "resources" / "base" / "media"
    svgs = list(media.glob("*.svg")) if media.exists() else []
    check("SVG icon set >= 30", len(svgs) >= 30, f"{len(svgs)} svgs")

    ets_count = len(list(ETS.rglob("*.ets")))
    notes.append(f"{ets_count} ArkTS files under ets/")

    print()
    for n in notes:
        print(f"note: {n}")
    if failures:
        print(f"RESULT: {len(failures)} check(s) failed")
        sys.exit(1)
    print("RESULT: all static checks passed")


if __name__ == "__main__":
    main()
