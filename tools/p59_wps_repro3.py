#!/usr/bin/env python3
"""P59-A repro v3: use the EXISTING active tab (attached webview) — navigate wps.cn + snapshot."""
import sys, time, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa

sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(1)
token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

# list existing tabs first
r = call_tool(qs, sid, 'tabs', {'action': 'list'})
print('tabs.list:', result_text(r)[:500])

# navigate the active tab (no tabId => active/first owned)
r = call_tool(qs, sid, 'navigate', {'url': 'https://www.wps.cn'}, timeout=120)
print('navigate:', result_text(r)[:300])
time.sleep(10)

r = call_tool(qs, sid, 'snapshot', {}, timeout=60)
snap = result_text(r)
print('snapshot len', len(snap))
idx = snap.find('在线使用')
print('在线使用 at', idx)
if idx >= 0:
    print('---context---')
    print(snap[max(0, idx-800):idx+800])
with open(r"D:\BrowserOS - KaihongOS\evidence\p59\p59_wps_snapshot1.txt", 'w', encoding='utf-8') as f:
    f.write(snap)
print('saved')
