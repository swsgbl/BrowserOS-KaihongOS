"""P40-A: check hilog private-mode options; fall back to plain -x cold capture."""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"

def sh(c, tmo=150):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

print('--- private help')
print(sh('hilog --help private 2>&1 | head -n 20'))
print('--- baselevel/privacy probe done; now plain cold capture')
sh('hilog -p off')
sh('hilog -r')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(10)
raw = sh('hilog -x -z 6000')
OUT = r"D:\BrowserOS - KaihongOS\evidence\p40\a8_cold_hilog.txt"
open(OUT, 'w', encoding='utf-8').write(raw)
lines = raw.splitlines()
print('total lines:', len(lines))
keep = [l for l in lines if any(k in l for k in ('mkdir cache', 'image_file_cache', 'get image data', 'rawFile', '9001001', 'drawable', 'resmgr', 'ImageSource'))]
print('matched:', len(keep))
for l in keep[:60]:
    print(l[:240])
