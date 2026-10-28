#!/usr/bin/env python3
"""P59-A/D verify via native click: screenshot -> find 在线使用 btn coords -> uinput click -> screenshot menu open."""
import sys, time, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
p59_keepalive.start()
time.sleep(2)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(3)
token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'about:blank'})
time.sleep(4)
r = call_tool(qs, sid, 'navigate', {'url': 'https://www.wps.cn'}, timeout=120)
print('navigate:', result_text(r)[:160])
time.sleep(12)

# before screenshot
sh('snapshot_display -f /data/local/tmp/p59_before.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_before.jpeg', EV + r"\p59_wps_before.jpeg"], capture_output=True)
print('before screenshot saved')

# wps.cn top nav: 在线使用 is one of the top-level buttons — coordinates from vision analysis next step.
# We click via uitest dump to find actual on-screen text bounds instead of guessing:
out = sh('uitest dumpLayout')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/layout.json', EV + r"\p59_wps_layout.json"], capture_output=True)
print('layout dumped')
p59_keepalive.stop()
