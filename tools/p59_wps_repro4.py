#!/usr/bin/env python3
"""P59-A repro v4: keepalive + clean app restart + single MCP session
tabs.new -> attach wait -> navigate wps.cn -> snapshot -> find 在线使用."""
import sys, time, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

p59_keepalive.start()
time.sleep(3)

# clean app restart
sh('aa force-stop com.browseros.kaihong')
time.sleep(2)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)

token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'about:blank'})
txt = result_text(r)
print('tabs.new:', txt[:200])
time.sleep(5)  # let ForEach render + controller attach

ok = False
for attempt in range(3):
    r = call_tool(qs, sid, 'navigate', {'url': 'https://www.wps.cn'}, timeout=120)
    t = result_text(r)
    print('navigate try%d:' % attempt, t[:160])
    if '"error"' not in t:
        ok = True
        break
    time.sleep(4)

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

# hilog trail
log = sh('hilog -x', tmo=40)
with open(r"D:\BrowserOS - KaihongOS\evidence\p59\p59_hilog_wps.txt", 'w', encoding='utf-8') as f:
    f.write(log)
print('saved; keepalive stopping')
p59_keepalive.stop()
