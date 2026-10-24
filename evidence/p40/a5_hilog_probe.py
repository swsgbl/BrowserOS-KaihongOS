"""P40-A: figure out why hilog -x returns nothing — probe hilog variants."""
import subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"

def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

print('--- hilog -x alone (first 5 lines)')
r = sh('hilog -x | head -n 5')
print(repr(r[:400]))
print('--- hilog -x count')
r = sh('hilog -x | wc -l')
print('lines:', r)
print('--- variant: hilog -z 100')
r = sh('hilog -z 100 2>&1 | head -n 3')
print(repr(r[:300]))
print('--- hilog --help | head')
r = sh('hilog --help 2>&1 | head -n 25')
print(r)
