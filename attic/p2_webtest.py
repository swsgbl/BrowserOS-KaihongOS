# -*- coding: utf-8 -*-
"""Web-component cleartext test: load http://10.0.2.2:11435/ in address bar"""
import subprocess, time, json
TARGET = '127.0.0.1:15566'
HDC_EXE = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
def sh(cmd, wait=0.3, timeout=60):
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')
def tap(x, y): sh(f'uitest uiInput click {x} {y}')
def dump():
    sh('uitest dumpLayout -p /data/local/tmp/wt.json', 1)
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/wt.json', r'D:\BrowserOS - KaihongOS\wt.json'], capture_output=True, timeout=30)
    return json.load(open(r'D:\BrowserOS - KaihongOS\wt.json', encoding='utf-8'))
def center(b):
    n = b.replace('[',' ').replace(']',' ').replace(',',' ').split()
    return (int(n[0])+int(n[2]))//2, (int(n[1])+int(n[3]))//2
def find_one(j, hint=None, text=None):
    stack, hits = [j], []
    while stack:
        x = stack.pop()
        if isinstance(x, dict):
            a = x.get('attributes') or {}
            ok = True
            if hint is not None and hint not in (a.get('hint') or ''): ok = False
            if text is not None and a.get('text','') != text: ok = False
            if ok and a.get('bounds','').count('[') == 2: hits.append(a)
            stack.extend(x.get('children') or [])
    return center(hits[0]['bounds']) if hits else None

sh('hilog -r', 0.5)
sh('aa start -a EntryAbility -b com.browseros.kaihong', 2)
j = dump()
addr = find_one(j, hint='输入URL或搜索关键词')
if not addr:
    # maybe on NeoDashboard: click home button first (⌂ or 返回)
    back = find_one(j, text='← 返回')
    if back:
        tap(*back); time.sleep(2); j = dump()
        addr = find_one(j, hint='输入URL或搜索关键词')
if not addr:
    home = find_one(j, text='⌂')
    if home:
        tap(*home); time.sleep(2); j = dump()
        addr = find_one(j, hint='输入URL或搜索关键词')
print('address bar @', addr, flush=True)
assert addr, 'no address bar'

x, y = addr
tap(x, y)
sh('uitest uiInput keyEvent 2016', 0.5)
sh(f"uitest uiInput inputText {x} {y} 'http://10.0.2.2:11435/'", 0.5)
sh('uitest uiInput keyEvent 2054', 0.5)
print('entered, waiting 12s', flush=True)
time.sleep(12)
sh('snapshot_display -f /data/local/tmp/webtest.jpeg', 1)
subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/webtest.jpeg', r'D:\BrowserOS - KaihongOS\webtest.jpeg'], capture_output=True, timeout=30)
r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
for l in (r.stdout or '').splitlines():
    if any(k in l for k in ('BrowserShell', 'net', 'Net', 'ERR_')):
        print(l, flush=True)
