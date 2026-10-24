"""P40-A step1: device-side raw truth of installed hap resources.
Pull /proc of the app process + verify resources.index version + rawfile presence,
then test resmgr readback via aace (systemui errors 9001001 recap from hilog).
Read-only on device.
"""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p40"

def sh(c, tmo=60):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()

def send(local, remote):
    r = subprocess.run([HDC, '-t', T, 'file', 'send', local, remote], capture_output=True, text=True, timeout=120)
    return ((r.stdout or '') + (r.stderr or '')).strip()

def recv(remote, local):
    r = subprocess.run([HDC, '-t', T, 'file', 'recv', remote, local], capture_output=True, text=True, timeout=120)
    return ((r.stdout or '') + (r.stderr or '')).strip()

# 1. where is the installed code + index
print('--- 1. bundle dir')
print(sh('ls /data/app/el1/bundle/public/ | grep browseros; ls /data/app/el2/100/base/ | grep browseros'))
print(sh('find /data/app -maxdepth 6 -name "resources.index" -path "*browseros*" 2>/dev/null'))

# 2. index head (first 64 bytes) via od on device
print('--- 2. installed index head')
p = sh('find /data/app/el1/bundle/public/com.browseros.kaihong -name resources.index 2>/dev/null | head -n1')
print('path:', p)
if p:
    print(sh('od -A d -t x1 -N 64 ' + p))

# 3. hap content list (the installed hap itself)
print('--- 3. installed hap')
hp = sh('find /data/app/el1/bundle/public/com.browseros.kaihong -name "*.hap" 2>/dev/null | head -n2')
print(hp)
