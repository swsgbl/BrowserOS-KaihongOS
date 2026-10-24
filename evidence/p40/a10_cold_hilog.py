"""P40-A: cold-start hilog — set privacy/clear as separate calls, then -x alone (no -z combo)."""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
OUT = r"D:\BrowserOS - KaihongOS\evidence\p40\a10_cold_hilog.txt"

def sh(c, tmo=200):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

print('privacy off:', sh('hilog -p off'))
print('clear:', sh('hilog -r'))
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(10)
raw = sh('hilog -x')
open(OUT, 'w', encoding='utf-8').write(raw)
lines = raw.splitlines()
print('total lines:', len(lines))
keep = [l for l in lines if any(k in l for k in ('mkdir cache', 'image_file_cache', 'get image data', 'rawFile', '9001001', 'drawable', 'resmgr', 'ImageSource'))]
print('matched:', len(keep))
for l in keep[:60]:
    print(l[:240])
