import sys, time, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

# settings gear at (420,319)
sh('uinput -T -c 420 319')
time.sleep(3)
sh('snapshot_display -f /data/local/tmp/p59_set.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_set.jpeg',
                r'D:\BrowserOS - KaihongOS\evidence\p59\p59_settings_open.jpeg'], capture_output=True)
print('settings shot saved')
