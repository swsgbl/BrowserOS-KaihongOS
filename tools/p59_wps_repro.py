#!/usr/bin/env python3
"""P59-A repro: navigate to wps.cn, dump page structure, find the 在线使用 menu,
click it via 'act', then snapshot to see whether the menu opened."""
import sys
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa

fport_up()
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(2)
token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)
print('session', sid[:8])

# fresh tab
r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'about:blank'})
txt = result_text(r)
print('tabs.new:', txt[:200])
tab_id = ''
try:
    j = json.loads(txt)
    tab_id = j.get('tabId') or j.get('tab_id') or j.get('id') or ''
except Exception:
    pass
print('tabId =', tab_id)

r = call_tool(qs, sid, 'navigate', {'url': 'https://www.wps.cn'}, timeout=120)
print('navigate:', result_text(r)[:300])

time.sleep(6)
r = call_tool(qs, sid, 'snapshot', {}, timeout=60)
snap = result_text(r)
print('snapshot len', len(snap))
# find 在线使用
idx = snap.find('在线使用')
print('在线使用 at', idx)
if idx >= 0:
    print(snap[max(0, idx-500):idx+500])
with open(r"D:\BrowserOS - KaihongOS\evidence\p59\p59_wps_snapshot1.txt", 'w', encoding='utf-8') as f:
    f.write(snap)
