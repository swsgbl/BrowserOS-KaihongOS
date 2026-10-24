"""P40-A step2: deep device-side probe of the installed hap + resmgr behavior."""
import subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"

def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

print('--- hap dir listing')
print(sh('ls -la /data/app/el1/bundle/public/com.browseros.kaihong/'))
print('--- hap head bytes (zip magic?)')
print(sh('od -A d -t x1 -N 8 /data/app/el1/bundle/public/com.browseros.kaihong/entry.hap'))
print('--- unzip listing via device (toybox unzip?)')
print(sh('which unzip; unzip -l /data/app/el1/bundle/public/com.browseros.kaihong/entry.hap 2>&1 | head -30'))
print('--- app data dirs')
print(sh('ls /data/app/el2/100/base/com.browseros.kaihong/ 2>/dev/null'))
print('--- cache dir (AceImage cache target)')
print(sh('ls -la /data/app/el2/100/base/com.browseros.kaihong/cache/ 2>/dev/null'))
print('--- els cache (el1/el2/el3 variants)')
print(sh('find /data/app -maxdepth 5 -name cache -path "*browseros*" 2>/dev/null'))
