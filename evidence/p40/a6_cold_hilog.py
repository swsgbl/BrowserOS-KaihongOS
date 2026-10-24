"""P40-A: cold-start hilog with privacy off, write to device file then pull (avoid pipe truncation)."""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
OUT = r"D:\BrowserOS - KaihongOS\evidence\p40\a6_cold_hilog.txt"

def sh(c, tmo=120):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

sh('hilog -r')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(10)

# dump whole buffer to a device file with privacy off
sh('hilog -x --privacy off > /data/local/tmp/p40log.txt 2>&1')
r = subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p40log.txt', OUT], capture_output=True, text=True, timeout=120, encoding='utf-8', errors='replace')
print('recv:', (r.stdout or r.stderr).strip())
raw = open(OUT, encoding='utf-8', errors='replace').read()
lines = raw.splitlines()
print('total lines:', len(lines))
keep = [l for l in lines if any(k in l for k in ('mkdir cache', 'image_file_cache', 'get image data', 'rawFile', '9001001', 'drawable', 'resmgr', 'ImageSource', 'CreatePixelMap'))]
print('matched:', len(keep))
for l in keep[:100]:
    print(l[:230])
