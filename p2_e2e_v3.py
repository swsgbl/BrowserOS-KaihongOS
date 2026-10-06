# -*- coding: utf-8 -*-
"""P2 e2e v3: wait for VM quiet window, then strike fast (60s UI) + poll hilog"""
import subprocess, time, json, os

TARGET = '127.0.0.1:15566'
HDC_EXE = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
OTHER_SESSION = r'C:\Users\hongfu\.hmharness\sessions\2026\10\06\2026-10-05T21-04-05-ylikgn.jsonl'

def sh(cmd, wait=0.3, timeout=60):
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')

def tap(x, y):
    sh(f'uitest uiInput click {x} {y}')

def activate():
    sh('uitest uiInput keyEvent 2016')

def type_text(x, y, text):
    tap(x, y); activate()
    sh(f"uitest uiInput inputText {x} {y} '{text}'", 0.4)

def dump():
    sh('uitest dumpLayout -p /data/local/tmp/e2e_now.json', 1)
    local = r'D:\BrowserOS - KaihongOS\e2e_now.json'
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/e2e_now.json', local], capture_output=True, text=True, timeout=30)
    return json.load(open(local, encoding='utf-8'))

def center(bounds):
    nums = bounds.replace('[', ' ').replace(']', ' ').replace(',', ' ').split()
    return (int(nums[0])+int(nums[2]))//2, (int(nums[1])+int(nums[3]))//2

def find_one(j, text=None, hint=None, type_=None):
    def p(a):
        if type_ and a.get('type') != type_: return False
        if text is not None and a.get('text', '') != text: return False
        if hint is not None and hint not in (a.get('hint') or ''): return False
        return a.get('bounds', '').count('[') == 2
    stack, hits = [j], []
    while stack:
        n = stack.pop()
        if isinstance(n, dict):
            a = n.get('attributes') or {}
            if p(a): hits.append(a)
            stack.extend(n.get('children') or [])
    return center(hits[0]['bounds']) if hits else None

# ---- Phase 0: wait for quiet window (other session file size stable 180s) ----
print('waiting for quiet window...', flush=True)
last_size = -1
quiet_since = None
deadline = time.time() + 3600
while time.time() < deadline:
    try:
        size = os.path.getsize(OTHER_SESSION) if os.path.exists(OTHER_SESSION) else 0
    except OSError:
        size = 0
    if size == last_size and last_size >= 0:
        if quiet_since is None: quiet_since = time.time()
        if time.time() - quiet_since >= 180:
            print('quiet window detected, striking', flush=True)
            break
    else:
        quiet_since = None
    last_size = size
    time.sleep(20)
else:
    print('no quiet window within 1h, proceeding anyway', flush=True)

# ---- Phase 1: bring app front and do UI fast ----
for attempt in range(4):
    sh('aa start -a EntryAbility -b com.browseros.kaihong', 1.5)
    j = dump()
    if find_one(j, text='查看代理'):
        break
    time.sleep(5)
else:
    raise SystemExit('BrowserOS home never reached foreground')

pos = find_one(j, text='查看代理')
tap(*pos); time.sleep(2)

j = dump()
name_p = find_one(j, hint='代理名称', type_='TextInput')
url_p = find_one(j, hint='目标URL', type_='TextInput')
task_p = find_one(j, hint='任务描述', type_='TextInput')
create_p = find_one(j, text='创建代理', type_='Button')
print('form:', name_p, url_p, task_p, create_p, flush=True)
assert all([name_p, url_p, task_p, create_p]), 'form fields incomplete'

type_text(*name_p, 't9')
type_text(*url_p, 'https://example.com')
type_text(*task_p, 'open the page and tell me the page title')
tap(*create_p)
print('=== agent created ' + time.strftime('%H:%M:%S') + ', polling hilog (foreground no longer needed) ===', flush=True)

# ---- Phase 2: poll hilog ----
end = time.time() + 300
seen_done = False
while time.time() < end:
    time.sleep(25)
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
    lines = [l for l in (r.stdout or '').splitlines() if any(k in l for k in ('AgentEngine', 'LLMClient', 'BCPEngine'))]
    print('--- poll ' + time.strftime('%H:%M:%S') + ' ---', flush=True)
    print('\n'.join(lines[-14:]), flush=True)
    joined = '\n'.join(lines).lower()
    if 'completed' in joined or 'task failed' in joined:
        seen_done = True
        break

sh('snapshot_display -f /data/local/tmp/e2e_final.jpeg', 1)
subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/e2e_final.jpeg', r'D:\BrowserOS - KaihongOS\e2e_final.jpeg'], capture_output=True, text=True, timeout=30)
print('=== done, seen_done=' + str(seen_done) + ' ===', flush=True)
