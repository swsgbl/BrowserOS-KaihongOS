# -*- coding: utf-8 -*-
"""diag4: state-aware strike + full error capture"""
import subprocess, time, json
TARGET = '127.0.0.1:15566'
HDC_EXE = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
def sh(cmd, wait=0.3, timeout=60):
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')
def tap(x, y): sh(f'uitest uiInput click {x} {y}')
def activate(): sh('uitest uiInput keyEvent 2016')
def type_text(x, y, t):
    tap(x, y); activate()
    sh(f"uitest uiInput inputText {x} {y} '{t}'", 0.4)
def dump():
    sh('uitest dumpLayout -p /data/local/tmp/d4.json', 1)
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/d4.json', r'D:\BrowserOS - KaihongOS\d4.json'], capture_output=True, timeout=30)
    return json.load(open(r'D:\BrowserOS - KaihongOS\d4.json', encoding='utf-8'))
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

def locate_form(j):
    f = {k: find_one(j, hint=h, type_='TextInput') for k, h in (('name','代理名称'),('url','目标URL'),('task','任务描述'))}
    f['create'] = find_one(j, text='创建代理', type_='Button')
    return f if all(f.values()) else None

sh('hilog -r', 0.5)
form = None
for attempt in range(10):
    sh('aa start -a EntryAbility -b com.browseros.kaihong', 2)
    j = dump()
    form = locate_form(j)
    if form:
        break
    btn = find_one(j, text='查看代理')
    if btn:
        tap(*btn); time.sleep(2)
        j = dump()
        form = locate_form(j)
        if form:
            break
    time.sleep(10)
else:
    raise SystemExit('cannot reach form')

type_text(*form['name'], 'diag4')
type_text(*form['url'], 'https://example.com')
type_text(*form['task'], 'hi')
tap(*form['create'])
print('created, waiting 10s', flush=True)
time.sleep(10)
r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
for l in (r.stdout or '').splitlines():
    if any(k in l for k in ('LLMClient', 'AgentEngine', 'SYS_', 'Context', 'BusinessError', '2301', 'rror')):
        print(l, flush=True)
