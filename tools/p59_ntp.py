#!/usr/bin/env python3
"""P59-E: click + (232,181) -> NTP dashboard -> find task TextInput -> type task -> Enter -> agent runs real LLM."""
import sys, time, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
p59_keepalive.start()
time.sleep(1)

sh('uinput -T -c 232 181')
time.sleep(4)

out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\p59_l_ntp2.json'], capture_output=True)
j = json.load(open(EV + '\\p59_l_ntp2.json', encoding='utf-8'))

inputs = []
hero = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    ty = (a.get('type', '') or '')
    t = a.get('text', '') or ''
    bid = (a.get('id', '') or '')
    b = a.get('bounds', '')
    if ty == 'TextInput':
        inputs.append((b, bid[:30]))
    if 'agent' in t.lower() or 'work on' in t.lower() or '描述' in t or '发送' in t:
        hero.append((t[:40], b))
    for c in (n.get('children') or []):
        w(c)


w(j)
print('inputs:', inputs)
print('hero:', hero[:6])
sh('snapshot_display -f /data/local/tmp/p59_ntp.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_ntp.jpeg', EV + '\\p59_ntp.jpeg'], capture_output=True)
p59_keepalive.stop()
