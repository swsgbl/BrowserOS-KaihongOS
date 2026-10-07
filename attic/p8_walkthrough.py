# -*- coding: utf-8 -*-
"""Round-3 walkthrough: tab visual / replay visual / bookmark / history / dark / ConfirmDialog"""
import subprocess, time, json
TARGET = '127.0.0.1:15566'
HDC = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
def sh(cmd, wait=0.3, timeout=60):
    r = subprocess.run([HDC, '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')
def tap(x, y): sh(f'uitest uiInput click {x} {y}')
def type_text(x, y, t):
    tap(x, y); sh('uitest uiInput keyEvent 2016', 0.3)
    sh(f"uitest uiInput inputText {x} {y} '{t}'", 0.3)
def snap(name):
    sh(f'snapshot_display -f /data/local/tmp/{name}', 1)
    subprocess.run([HDC, '-t', TARGET, 'file', 'recv', f'/data/local/tmp/{name}', rf'D:\BrowserOS - KaihongOS\{name}'], capture_output=True, timeout=30)
    print('shot', name, flush=True)
def dump(name='w3.json'):
    sh(f'uitest dumpLayout -p /data/local/tmp/{name}', 0.8)
    subprocess.run([HDC, '-t', TARGET, 'file', 'recv', f'/data/local/tmp/{name}', rf'D:\BrowserOS - KaihongOS\{name}'], capture_output=True, timeout=30)
    return json.load(open(rf'D:\BrowserOS - KaihongOS\{name}', encoding='utf-8'))
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

def logs(kws):
    r = subprocess.run([HDC, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
    return [l for l in (r.stdout or '').splitlines() if any(k in l for k in kws)]

# ---------- 1. Create agent (for tab visual + replay) ----------
sh('hilog -r', 0.5)
sh('aa force-stop com.browseros.kaihong', 1.5)
sh('aa start -a EntryAbility -b com.browseros.kaihong', 3)
j = dump()
ag = find_one(j, text='查看代理')
assert ag, 'no dashboard'
tap(*ag); time.sleep(2)
j = dump()
f = {k: find_one(j, hint=h, type_='TextInput') for k, h in (('name','代理名称'),('url','目标URL'),('task','任务描述'))}
f['create'] = find_one(j, text='创建代理', type_='Button')
assert all(f.values()), f'form missing {f}'
type_text(*f['name'], 'w3demo')
type_text(*f['url'], 'https://example.com')
type_text(*f['task'], 'open the page and tell me the page title')
tap(*f['create'])
print('agent created, waiting for parallel-web auto-run...', flush=True)
# while agent runs, go back to browser shell for tab visual
time.sleep(2)
j = dump()
back = find_one(j, text='← 返回')
if back:
    tap(*back); time.sleep(2)
snap('w3_tabs.jpeg')  # walkthrough-1: three tabs visual

# ---------- 2. Bookmark: navigate a manual tab then star it ----------
j = dump()
addr = find_one(j, hint='输入URL或搜索关键词')
if addr:
    type_text(*addr, 'https://example.com')
    sh('uitest uiInput keyEvent 2054', 2.5)
    star = find_one(j, text='☆')  # from previous dump; coordinates may shift little
    j2 = dump('w3b.json')
    star = find_one(j2, text='☆')
    if star:
        tap(*star); time.sleep(1.5)
        bm = [l for l in logs(['Bookmark', 'bookmark'])]
        print('=== bookmark logs ===', flush=True)
        print('\n'.join(bm[-4:]) or '(none)', flush=True)
        # dashboard count check
        home = find_one(j2, text='⌂')
        if home:
            tap(*home); time.sleep(1.5)
            j3 = dump('w3c.json')
            cnt = None
            stack = [j3]
            while stack:
                x = stack.pop()
                if isinstance(x, dict):
                    a = x.get('attributes') or {}
                    t = a.get('text') or ''
                    if t.startswith('书签'):
                        cnt = t
                        break
                    stack.extend(x.get('children') or [])
            print('bookmark counter text:', cnt, flush=True)
            snap('w3_dark.jpeg')  # walkthrough-5: dark theme visual (dashboard)

# ---------- 3. History panel ----------
j4 = dump('w3d.json')
hist = find_one(j4, text='🕘')
if hist:
    tap(*hist); time.sleep(2)
    snap('w3_history.jpeg')
    hl = [l for l in logs(['History', 'history'])]
    print('=== history logs ===', flush=True)
    print('\n'.join(hl[-4:]) or '(none)', flush=True)

# ---------- 4. Replay visual (agent should be done by now) ----------
j5 = dump('w3e.json')
ag2 = find_one(j5, text='查看代理')
if ag2:
    tap(*ag2); time.sleep(2)
    j6 = dump('w3f.json')
    replay = find_one(j6, text='回放')
    if replay:
        tap(*replay); time.sleep(4)
        snap('w3_replay.jpeg')  # walkthrough-2: replay visual
        rl = [l for l in logs(['SessionPlayer'])]
        print('=== replay logs ===', flush=True)
        print('\n'.join(rl[-4:]) or '(none)', flush=True)
    else:
        print('replay btn not present (agent card missing?)', flush=True)

# ---------- 5. ConfirmDialog e2e: URL with sensitive keyword on real page ----------
j7 = dump('w3g.json')
addr = find_one(j7, hint='输入URL或搜索关键词')
if not addr:
    home = find_one(j7, text='⌂')
    if home:
        tap(*home); time.sleep(1.5)
        j7 = dump('w3h.json')
        addr = find_one(j7, hint='输入URL或搜索关键词')
if addr:
    type_text(*addr, 'https://example.com/pay')
    sh('uitest uiInput keyEvent 2054', 4)
    sd = [l for l in logs(['ensitive', 'onfirm', 'SENSITIVE'])]
    print('=== sensitive logs ===', flush=True)
    print('\n'.join(sd[-6:]) or '(none)', flush=True)
    j8 = dump('w3i.json')
    cfm = find_one(j8, text='确认') or find_one(j8, text='允许')
    print('confirm dialog present:', cfm, flush=True)
    if cfm:
        snap('w3_confirm.jpeg')  # walkthrough-6: confirm dialog visual
        tap(*cfm); time.sleep(1.5)
        rs = [l for l in logs(['resolve', 'RESOLVED', 'CONFIRMED', 'sensitive'])]
        print('after confirm:', '\n'.join(rs[-4:]) or '(none)', flush=True)
print('=== ROUND-3 WALKTHROUGH DONE ===', flush=True)
