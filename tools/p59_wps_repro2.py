#!/usr/bin/env python3
"""P59-A repro v2: navigate (retry attach), snapshot wps.cn, find menu."""
import sys, time, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa

sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(1)
token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'about:blank'})
txt = result_text(r)
print('tabs.new:', txt[:200])
tab_id = json.loads(txt).get('tabId', '')
time.sleep(3)

ok = False
for attempt in range(4):
    r = call_tool(qs, sid, 'navigate', {'url': 'https://www.wps.cn', 'tabId': tab_id}, timeout=120)
    t = result_text(r)
    print('navigate try%d:' % attempt, t[:200])
    if 'error' not in t:
        ok = True
        break
    time.sleep(3)

time.sleep(8)
r = call_tool(qs, sid, 'snapshot', {}, timeout=60)
snap = result_text(r)
print('snapshot len', len(snap))
idx = snap.find('在线使用')
print('在线使用 at', idx)
if idx >= 0:
    print('---context---')
    print(snap[max(0, idx-700):idx+700])
with open(r"D:\BrowserOS - KaihongOS\evidence\p59\p59_wps_snapshot1.txt", 'w', encoding='utf-8') as f:
    f.write(snap)
print('saved')
