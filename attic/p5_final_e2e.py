# -*- coding: utf-8 -*-
"""P5 FINAL: create agent, immediately click its tab while alive, verify BCP+screenshots+COMPLETED"""
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
    sh('uitest dumpLayout -p /data/local/tmp/p5f.json', 0.8)
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/p5f.json', r'D:\BrowserOS - KaihongOS\p5f2.json'], capture_output=True, timeout=30)
    return json.load(open(r'D:\BrowserOS - KaihongOS\p5f2.json', encoding='utf-8'))
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
btn = None
for attempt in range(8):
    sh('aa start -a EntryAbility -b com.browseros.kaihong', 1.5)
    j = dump()
    btn = find_one(j, text='查看代理')
    if btn:
        break
    home = find_one(j, text='⌂')
    if home and find_one(j, hint='输入URL或搜索关键词'):
        tap(*home); time.sleep(2)
        j = dump()
        btn = find_one(j, text='查看代理')
        if btn:
            break
    time.sleep(6)
if not btn:
    raise SystemExit('no 查看代理 after retries')
tap(*btn); time.sleep(2)
j = dump()
f = {k: find_one(j, hint=h, type_='TextInput') for k, h in (('name','代理名称'),('url','目标URL'),('task','任务描述'))}
f['create'] = find_one(j, text='创建代理', type_='Button')
assert all(f.values()), f'form missing {f}'
type_text(*f['name'], 'zfinal')
type_text(*f['url'], 'https://example.com')
type_text(*f['task'], 'open the page and tell me the page title')
tap(*f['create'])
print('agent created at ' + time.strftime('%H:%M:%S') + ', rushing back to tab strip...', flush=True)
time.sleep(0.8)

# rush back to BrowserShell and click the Agent tab (last tab, titled zfinal/Agent...)
j = dump()
back = find_one(j, text='← 返回')
if back:
    tap(*back); time.sleep(1.2)
j = dump()
tabs = []
stack = [j]
while stack:
    x = stack.pop()
    if isinstance(x, dict):
        a = x.get('attributes') or {}
        b = a.get('bounds', '')
        if a.get('type') == 'Text' and b.count('[') == 2:
            nums = b.replace('[',' ').replace(']',' ').replace(',',' ').split()
            if len(nums) == 4 and 230 < int(nums[1]) < 300 and (a.get('text') or '').strip():
                tabs.append(((int(nums[0])+int(nums[2]))//2, (int(nums[1])+int(nums[3]))//2, (a.get('text') or '')[:20]))
print('tabs:', tabs, flush=True)
agent_tab = next((t for t in tabs if 'zfinal' in t[2] or 'Agent' in t[2] or '代理' in t[2]), None)
if agent_tab:
    print('CLICKING agent tab:', agent_tab, flush=True)
    tap(agent_tab[0], agent_tab[1])
else:
    print('agent tab not found in strip, tabs were:', tabs, flush=True)

# poll for the full chain
end = time.time() + 240
while time.time() < end:
    time.sleep(25)
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
    lines = [l for l in (r.stdout or '').splitlines() if any(k in l for k in ('AgentEngine', 'LLMClient', 'BCPEngine', 'SessionManager', 'onPageEnd', 'capture', 'screenshot'))]
    print('--- poll ' + time.strftime('%H:%M:%S') + ' ---', flush=True)
    print('\n'.join(lines[-14:]) or '(quiet)', flush=True)
    joined = '\n'.join(lines).lower()
    if 'completed' in joined or 'task failed' in joined:
        break

# final: sessions JSON screenshots
r = sh('ls /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/sessions/')
names = [l.strip() for l in r.splitlines() if l.strip().endswith('.json')]
for name in names[-2:]:
    c = sh(f'cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/sessions/{name}')
    try:
        j2 = json.loads(c)
        print(f'{name}: operationLogs={len(j2.get("operationLogs",[]))} screenshots={len(j2.get("screenshots",[]))}', flush=True)
    except Exception as e:
        print(name, 'err', str(e)[:80], flush=True)
print('=== P5 FINAL DONE ===', flush=True)
