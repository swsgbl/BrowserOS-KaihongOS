#!/usr/bin/env python3
"""P59-A/D final: fresh nav to wps.cn in foreground browser, click 在线使用, screenshot dropdown."""
import sys, time, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
p59_keepalive.start()
time.sleep(2)

token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)
r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'about:blank'})
time.sleep(4)
r = call_tool(qs, sid, 'navigate', {'url': 'https://www.wps.cn'}, timeout=120)
print('navigate:', result_text(r)[:160])
time.sleep(14)

# browser foreground: click app window title area first to ensure focus belongs to browser
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(2)

# click 在线使用 at (843,326) then screenshot
sh('uinput -T -c 843 326')
time.sleep(2.5)
sh('snapshot_display -f /data/local/tmp/p59_menu2.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_menu2.jpeg', EV + r"\p59_wps_menu_open2.jpeg"], capture_output=True)
print('menu screenshot saved')

# hover variant: move over the button (some menus open on hover)
sh('uinput -T -m 700 326 843 326 600')
time.sleep(2.5)
sh('snapshot_display -f /data/local/tmp/p59_menu3.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_menu3.jpeg', EV + r"\p59_wps_menu_hover.jpeg"], capture_output=True)
print('hover screenshot saved')
p59_keepalive.stop()
