#!/usr/bin/env python3
"""P59-E Agent E2E: MCP new tab (NTP) -> find task input -> type Chinese task -> Enter -> watch agent run real LLM."""
import sys, time, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
p59_keepalive.start()
time.sleep(2)

token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

# new tab -> NTP with agent task box
r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': ''})
print('tabs.new:', result_text(r)[:140])
time.sleep(6)

# dump layout to find the task input
out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\p59_l_ntp.json'], capture_output=True)
j = json.load(open(EV + '\\p59_l_ntp.json', encoding='utf-8'))
res = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    t = a.get('text', '') or ''
    bid = (a.get('id', '') or '')
    ty = (a.get('type', '') or '')
    if t and ('描述' in t or 'Enter' in t or '发送' in t or '目标' in t):
        res.append((t[:40], a.get('bounds', ''), bid[:20]))
    if ty == 'TextInput' or 'textarea' in ty.lower() or bid:
        res.append(('TYPE:' + ty, a.get('bounds', ''), bid[:24]))
    for c in (n.get('children') or []):
        w(c)


w(j)
for x in res[:12]:
    print(x)
p59_keepalive.stop()
