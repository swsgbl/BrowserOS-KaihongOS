"""P40-A: launch STORED build + privacy-off hilog check for rawfile/media errors + screenshot."""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p40"

def sh(c, tmo=120):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

print('privacy:', sh('hilog -p off'))
print('clear:', sh('hilog -r'))
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(10)
raw = sh('hilog -x')
open(EV + r'\a15_stored_hilog.txt', 'w', encoding='utf-8').write(raw)
lines = raw.splitlines()
print('total lines:', len(lines))
errs = [l for l in lines if any(k in l for k in ('Get rawFile from hap error', 'get image data by name failed', 'Failed to Create drawableDescriptor', 'mkdir cache file path failed', 'Get string by id error'))]
print('RESOURCE ERRORS:', len(errs))
for l in errs[:30]:
    print('  ', l[:200])
oks = [l for l in lines if 'CreatePixelMap success' in l or 'OnImageLoaded' in l]
print('image OK markers:', len(oks))
for l in oks[:10]:
    print('  ', l[:200])
# screenshot
sh('snapshot_display -f /data/local/tmp/p40_stored.jpeg')
r = subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p40_stored.jpeg', EV + r'\a15_stored.jpeg'], capture_output=True, text=True, timeout=60, encoding='utf-8', errors='replace')
print('shot:', (r.stdout or r.stderr).strip())
