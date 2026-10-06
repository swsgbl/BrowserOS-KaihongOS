# -*- coding: utf-8 -*-
"""Verify cookies import: dashboard -> import button -> hilog"""
import subprocess, time, json
TARGET = '127.0.0.1:15566'
HDC_EXE = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
def sh(cmd, wait=0.3, timeout=60):
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')
def tap(x, y): sh(f'uitest uiInput click {x} {y}')
def dump():
    sh('uitest dumpLayout -p /data/local/tmp/p7c.json', 0.8)
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/p7c.json', r'D:\BrowserOS - KaihongOS\p7c.json'], capture_output=True, timeout=30)
    return json.load(open(r'D:\BrowserOS - KaihongOS\p7c.json', encoding='utf-8'))
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
sh('aa force-stop com.browseros.kaihong', 1.5)
sh('aa start -a EntryAbility -b com.browseros.kaihong', 2.5)
j = dump()
btn = find_one(j, text='导入登录态')
if not btn:
    print('dashboard text missing; visible:', flush=True)
    stack=[j]
    while stack:
        x = stack.pop()
        if isinstance(x, dict):
            a = x.get('attributes') or {}
            if (a.get('text') or '').strip():
                print(' ', a.get('text'), a.get('bounds'), flush=True)
            stack.extend(x.get('children') or [])
    raise SystemExit('no import button')
print('import btn:', btn, flush=True)
tap(*btn)
time.sleep(2)
# after click: may open dialog with path input + import
j = dump()
imp = find_one(j, text='导入') or find_one(j, text='确定')
path_in = find_one(j, hint='路径') or find_one(j, hint='cookies')
print('dialog: import=', imp, 'path_input=', path_in, flush=True)
if path_in:
    tap(*path_in)
    sh('uitest uiInput keyEvent 2016', 0.4)
    sh(f"uitest uiInput inputText {path_in[0]} {path_in[1]} 'cookies.json'", 0.5)
if imp:
    tap(*imp)
time.sleep(3)
r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
for l in (r.stdout or '').splitlines():
    if any(k in l for k in ('LoginState', 'cookie', 'Cookie', 'import')):
        print(l, flush=True)
print('=== COOKIE IMPORT VERIFY DONE ===', flush=True)
