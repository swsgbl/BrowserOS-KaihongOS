#!/usr/bin/env python3
"""P59-A/D verify: wps.cn loads with DOM storage -> 在线使用 menu clickable."""
import sys, time, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

p59_keepalive.start()
time.sleep(2)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(5)

token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'about:blank'})
print('tabs.new:', result_text(r)[:120])
time.sleep(4)

r = call_tool(qs, sid, 'navigate', {'url': 'https://www.wps.cn'}, timeout=120)
print('navigate:', result_text(r)[:200])
time.sleep(12)

r = call_tool(qs, sid, 'snapshot', {}, timeout=90)
snap = result_text(r)
print('snapshot len', len(snap))
idx = snap.find('在线使用')
print('在线使用 at', idx)
if idx >= 0:
    print('---context---')
    print(snap[max(0, idx-600):idx+600])
with open(r"D:\BrowserOS - KaihongOS\evidence\p59\p59_wps_snapshot2.txt", 'w', encoding='utf-8') as f:
    f.write(snap)

# hilog: look for the localStorage crash
log = sh('hilog -x', tmo=40)
with open(r"D:\BrowserOS - KaihongOS\evidence\p59\p59_hilog_wps2.txt", 'w', encoding='utf-8') as f:
    f.write(log)
crash = 'getItem' in log and 'chunk-common' in log
print('localStorage crash still present?', crash)
p59_keepalive.stop()
