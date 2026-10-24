"""P40 final: screenshots for evidence + full diff summary."""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p40"

def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

# fresh cold start + icon-rich screenshot
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)
sh('snapshot_display -f /data/local/tmp/p40_final.jpeg')
r = subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p40_final.jpeg', EV + r'\p40_final.jpeg'], capture_output=True, text=True, timeout=60, encoding='utf-8', errors='replace')
print('shot:', (r.stdout or r.stderr).strip())
