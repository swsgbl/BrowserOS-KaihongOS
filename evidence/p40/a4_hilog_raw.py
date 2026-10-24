"""P40-A: fresh hilog, raw dump then local filter (device grep may be empty due to buffering)."""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
OUT = r"D:\BrowserOS - KaihongOS\evidence\p40\a4_hilog_raw.txt"

def sh(c, tmo=120):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

sh('hilog -r')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(9)

raw = sh('hilog -x --privacy off 2>/dev/null | head -n 4000')
open(OUT, 'w', encoding='utf-8').write(raw)
lines = raw.splitlines()
print('total lines:', len(lines))
keep = [l for l in lines if any(k in l for k in ('mkdir cache', 'image_file_cache', 'get image data', 'rawFile', '9001001', 'drawable', 'resmgr', 'ImageSource', 'CreatePixelMap', 'image'))]
print('matched:', len(keep))
for l in keep[:80]:
    print(l[:220])
