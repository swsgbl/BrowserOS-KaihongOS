#!/usr/bin/env python3
"""P59-D verify: click 在线使用 menu on wps.cn via act; screenshot evidence."""
import sys, time, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

p59_keepalive.start()
time.sleep(1)
token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

# take fresh snapshot with refs
r = call_tool(qs, sid, 'snapshot', {}, timeout=90)
snap = result_text(r)
with open(r"D:\BrowserOS - KaihongOS\evidence\p59\p59_wps_snapshot3.txt", 'w', encoding='utf-8') as f:
    f.write(snap)

# find the ref for 在线使用 — refs array in result
refs = []
try:
    j = json.loads(snap)
    refs = j.get('result', {}).get('refs', [])
except Exception:
    # content field format
    pass
print('refs count:', len(refs))

target = ''
for ref in refs:
    txt = json.dumps(ref, ensure_ascii=False)
    if '在线使用' in txt:
        print('FOUND ref:', txt[:200])
        target = str(ref.get('ref', ref.get('rid', '')))
        break
print('target ref =', target)

if target:
    r = call_tool(qs, sid, 'act', {'action': 'click', 'ref': target}, timeout=60)
    print('act.click:', result_text(r)[:300])
    time.sleep(3)
    # screenshot the open dropdown
    sh('snapshot_display -f /data/local/tmp/p59_menu1.jpeg')
    import subprocess
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_menu1.jpeg',
                    r'D:\BrowserOS - KaihongOS\evidence\p59\p59_wps_menu_open.jpeg'], capture_output=True)
    # second snapshot to see menu content in DOM
    r = call_tool(qs, sid, 'snapshot', {}, timeout=90)
    snap2 = result_text(r)
    with open(r"D:\BrowserOS - KaihongOS\evidence\p59\p59_wps_snapshot_after_click.txt", 'w', encoding='utf-8') as f:
        f.write(snap2)
    print('after-click snapshot len', len(snap2))
else:
    print('NO REF FOUND for 在线使用')
p59_keepalive.stop()
