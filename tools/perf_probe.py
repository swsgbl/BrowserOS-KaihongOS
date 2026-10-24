#!/usr/bin/env python3
"""P38: reusable performance probe (P36 debt) — cold start + memory sampling.

Cold start: force-stop + aa start, read hilog [P36] cold_start_ms=NNN (printed
by BrowserShell aboutToAppear end), repeat N rounds.
Memory: hidumper --mem <pid>, report total PSS.

Usage: python tools/perf_probe.py [--rounds 3]
"""
import argparse
import re
import subprocess
import sys
import time

HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
BUNDLE = "com.browseros.kaihong"


def sh(cmd, tmo=90):
    r = subprocess.run([HDC, "-t", T, "shell", cmd], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or "") + (r.stderr or "")).strip()


def one_cold_start():
    sh("hilog -r")
    sh("aa force-stop %s" % BUNDLE)
    time.sleep(1)
    sh("aa start -a EntryAbility -b %s" % BUNDLE)
    time.sleep(6)
    out = sh("hilog -x")
    m = re.findall(r"cold_start_ms=(\d+)", out)
    return int(m[-1]) if m else None


def memory_pss():
    pid_out = sh("pidof %s" % BUNDLE)
    pid = pid_out.split()[0] if pid_out.split() else ''
    if not pid:
        return None
    out = sh("hidumper --mem %s" % pid, tmo=120)
    m = re.search(r"Total PSS[:\s]+(\d+)", out)
    return int(m.group(1)) if m else None


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=3)
    args = ap.parse_args()
    print("== BrowserOS perf probe (Quickemu VM %s) ==" % T)
    times = []
    for i in range(args.rounds):
        ms = one_cold_start()
        print("round %d: cold_start_ms=%s" % (i + 1, ms))
        if ms:
            times.append(ms)
    if times:
        print("cold start avg: %d ms (n=%d)" % (sum(times) // len(times), len(times)))
    time.sleep(8)
    pss = memory_pss()
    print("memory PSS: %s kB" % pss)


if __name__ == "__main__":
    main()
