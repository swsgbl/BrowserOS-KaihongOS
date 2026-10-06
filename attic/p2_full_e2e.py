# -*- coding: utf-8 -*-
"""FINAL P2 e2e: real task + activate agent tab + full loop to completion"""
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
    sh('uitest dumpLayout -p /data/local/tmp/fx.json', 1)
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/fx.json', r'D:\BrowserOS - KaihongOS\fx.json'], capture_output=True, timeout=30)
    return json.load(open(r'D:\BrowserOS - KaihongOS\fx.json', encoding='utf-8'))
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
for attempt in range(8):
    sh('aa start -a EntryAbility -b com.browseros.kaihong', 2)
    j = dump()
    form = locate_form(j)
    if form: break
    btn = find_one(j, text='查看代理')
    if btn:
        tap(*btn); time.sleep(2)
        j = dump()
        form = locate_form(j)
        if form: break
    time.sleep(8)
else:
    raise SystemExit('cannot reach form')

type_text(*form['name'], 'tFinal')
type_text(*form['url'], 'https://example.com')
type_text(*form['task'], 'open the page and tell me the page title')
tap(*form['create'])
print('agent created, activating its tab...', flush=True)
time.sleep(2)

# go back to browser shell to see tab strip, click the newest tab
back = None
j = dump()
back = find_one(j, text='← 返回')
if back:
    tap(*back); time.sleep(2)
    j = dump()

# find tab strip texts (tab titles around y~87-100); click last tab that is not the current one
tabs = []
stack = [j]
while stack:
    x = stack.pop()
    if isinstance(x, dict):
        a = x.get('attributes') or {}
        b = a.get('bounds', '')
        if a.get('type') == 'Text' and b.startswith('[') and b.count('[') == 2:
            nums = b.replace('[',' ').replace(']',' ').replace(',',' ').split()
            if len(nums) == 4 and 60 < int(nums[1]) < 130:
                tabs.append(((int(nums[0])+int(nums[2]))//2, (int(nums[1])+int(nums[3]))//2, (a.get('text') or '')[:20]))
        stack.extend(x.get('children') or [])
print('tab strip texts:', tabs, flush=True)
if len(tabs) >= 2:
    # click the rightmost tab that isn't marked with the dashboard
    tx, ty, tt = tabs[-1]
    print('clicking tab:', tx, ty, tt, flush=True)
    tap(tx, ty)
    time.sleep(4)

print('watching loop...', flush=True)
end = time.time() + 300
while time.time() < end:
    time.sleep(25)
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
    lines = [l for l in (r.stdout or '').splitlines() if any(k in l for k in ('AgentEngine', 'LLMClient', 'BCPEngine', 'BrowserShell navigate'))]
    print('--- poll ' + time.strftime('%H:%M:%S') + ' ---', flush=True)
    print('\n'.join(lines[-15:]) or '(quiet)', flush=True)
    joined = '\n'.join(lines).lower()
    if 'completed' in joined or 'task failed' in joined:
        break

sh('snapshot_display -f /data/local/tmp/final_e2e.jpeg', 1)
subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/final_e2e.jpeg', r'D:\BrowserOS - KaihongOS\final_e2e.jpeg'], capture_output=True, timeout=30)
print('=== FINAL DONE ===', flush=True)
