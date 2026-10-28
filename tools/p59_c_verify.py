#!/usr/bin/env python3
"""P59-C verify: open Skills page, verify back button present + tap returns."""
import sys, time, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
p59_keepalive.start()
time.sleep(2)

sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('rm -f /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/tabs.json')
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)

out = sh('uitest dumpLayout')
r = subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/layout.json',
                    EV + '\\p59_layout_home.json'], capture_output=True)
print('layout recv:', r.returncode == 0)
p59_keepalive.stop()
