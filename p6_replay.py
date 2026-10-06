# -*- coding: utf-8 -*-
"""P6 replay verification: open replay for the session with 8 screenshots"""
import subprocess, time, json
TARGET = '127.0.0.1:15566'
HDC_EXE = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
def sh(cmd, wait=0.3, timeout=60):
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')
def tap(x, y): sh(f'uitest uiInput click {x} {y}')
def dump():
    sh('uitest dumpLayout -p /data/local/tmp/p6r.json', 0.8)
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/p6r.json', r'D:\BrowserOS - KaihongOS\p6r.json'], capture_output=True, timeout=30)
    return json.load(open(r'D:\BrowserOS - KaihongOS\p6r.json', encoding='utf-8'))
def center(b):
    n = b.replace('[',' ').replace(']',' ').replace(',',' ').split()
    return (int(n[0])+int(n[2]))//2, (int(n[1])+int(n[3]))//2
def find_one(j, text=None, hint=None, type_=None):
    stack, hits = [j], []
    while stack:
        x = stack.pop()
        if isinstance(x, dict):
            a = x.get('attributes') or {}
            ok = True
            if type_ and a.get('type') != type_: ok = False
            if text is not None and a.get('text','') != text: ok = False
            if hint is not None and hint not in (a.get('hint') or ''): ok = False
            if ok and a.get('bounds','').count('[') == 2: hits.append(a)
            stack.extend(x.get('children') or [])
    return center(hits[0]['bounds']) if hits else None

sh('hilog -r', 0.5)
j = dump()
panel = find_one(j, text='查看代理') or find_one(j, text='创建新代理')
if panel:
    tap(*panel); time.sleep(2)
j = dump()
replay = find_one(j, text='回放') or find_one(j, hint='回放')
print('replay btn:', replay, flush=True)
assert replay, 'no replay button found'
tap(*replay)
time.sleep(4)
r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
for l in (r.stdout or '').splitlines():
    if any(k in l for k in ('SessionPlayer', 'Replayer', 'screenshot', '回放')):
        print(l, flush=True)
sh('snapshot_display -f /data/local/tmp/replay.jpeg', 1)
subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/replay.jpeg', r'D:\BrowserOS - KaihongOS\replay.jpeg'], capture_output=True, timeout=30)
print('=== REPLAY VERIFY DONE ===', flush=True)
