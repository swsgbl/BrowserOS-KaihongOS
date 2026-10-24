"""P40-A: capture FRESH hilog with --privacy off during a cold app start,
to unmask the mkdir cache path and the rawFile name."""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
OUT = r"D:\BrowserOS - KaihongOS\evidence\p40\a3_hilog_privacy.txt"

def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

# 1. clear buffer, cold start app
sh('hilog -r')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)

# 2. dump with privacy off, filter AceImage + resmgr + 9001001
raw = sh('hilog -x --privacy off 2>&1 | grep -i -E "mkdir cache|image_file_cache|get image data|rawFile|9001001|drawable|AceImage|resmgr" | head -n 120')
open(OUT, 'w', encoding='utf-8').write(raw)
print(raw)
print('--- saved to', OUT)
