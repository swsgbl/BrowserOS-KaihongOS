#!/usr/bin/env python3
"""P59-E config attempt: open Settings LLM section, type into ArkUI TextInput via uitest uiInput text."""
import sys, time, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
p59_keepalive.start()
time.sleep(1)

# app is running (neo mode). Settings entry: sidebar gear — but window geometry shifts.
# Robust: dump layout, find 设置 text inside BROWSER window (x>211), else use tab panel.
out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\p59_l_setfind.json'], capture_output=True)
j = json.load(open(EV + '\\p59_l_setfind.json', encoding='utf-8'))
cands = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    t = a.get('text', '') or ''
    if t.strip() == '设置' or 'LLM' in t:
        cands.append((t.strip()[:12], a.get('bounds', '')))
    for c in (n.get('children') or []):
        w(c)


w(j)
print(json.dumps(cands[:8], ensure_ascii=False))
p59_keepalive.stop()
