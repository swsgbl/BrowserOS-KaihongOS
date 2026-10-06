# -*- coding: utf-8 -*-
"""P6 acceptance rerun: full e2e with live hilog capture"""
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
    sh(f"uitest uiInput inputText {x} {y} '{t}'", 0.3)
def dump():
    sh('uitest dumpLayout -p /data/local/tmp/p6v.json', 0.8)
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/p6v.json', r'D:\BrowserOS - KaihongOS\p6v.json'], capture_output=True, timeout=30)
    return json.load(open(r'D:\BrowserOS - KaihongOS\p6v.json', encoding='utf-8'))
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
# fresh restart to dashboard
sh('aa force-stop com.browseros.kaihong', 1.5)
sh('aa start -a EntryAbility -b com.browseros.kaihong', 2.5)
j = dump()
btn = find_one(j, text='查看代理')
assert btn, 'dashboard not reached'
tap(*btn); time.sleep(2)
j = dump()
f = {k: find_one(j, hint=h, type_='TextInput') for k, h in (('name','代理名称'),('url','目标URL'),('task','任务描述'))}
f['create'] = find_one(j, text='创建代理', type_='Button')
assert all(f.values()), f'form missing {f}'
type_text(*f['name'], 'p6verify')
type_text(*f['url'], 'https://example.com')
type_text(*f['task'], 'open the page and tell me the page title')
tap(*f['create'])
print('=== agent created ' + time.strftime('%H:%M:%S') + ' — ZERO manual intervention from here ===', flush=True)

all_lines = []
end = time.time() + 300
while time.time() < end:
    time.sleep(20)
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
    lines = [l for l in (r.stdout or '').splitlines() if any(k in l for k in ('AgentEngine', 'LLMClient', 'BCPEngine', 'SessionManager', 'onPageEnd', 'capture', 'completed'))]
    all_lines = lines
    print('--- poll ' + time.strftime('%H:%M:%S') + ' ---', flush=True)
    print('\n'.join(lines[-10:]) or '(quiet)', flush=True)
    joined = '\n'.join(lines).lower()
    if 'completed' in joined or 'task failed' in joined:
        break

# final state
r = sh('ls /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/sessions/')
names = [l.strip() for l in r.splitlines() if l.strip().endswith('.json')]
last = names[-1]
c = sh(f'cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/sessions/{last}')
try:
    j2 = json.loads(c)
    print(f'FINAL {last}: opLogs={len(j2.get("operationLogs",[]))} screenshots={len(j2.get("screenshots",[]))}', flush=True)
except Exception as e:
    print(last, 'err', str(e)[:80], flush=True)
print('=== P6 VERIFY DONE ===', flush=True)
