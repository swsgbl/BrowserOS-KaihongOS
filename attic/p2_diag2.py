# -*- coding: utf-8 -*-
import subprocess, time
TARGET = '127.0.0.1:15566'
HDC_EXE = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
def sh(cmd, wait=0.3, timeout=60):
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')

sh('hilog -r', 0.5)
sh('uitest uiInput click 800 321', 1)
print('create clicked, waiting 15s...', flush=True)
time.sleep(15)
r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
for l in (r.stdout or '').splitlines():
    if any(k in l for k in ('JSAPP', 'LLM', 'Agent', '2301', 'rror')):
        print(l, flush=True)
