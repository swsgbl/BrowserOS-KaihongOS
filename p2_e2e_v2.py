# -*- coding: utf-8 -*-
"""P2 e2e final v2: fully dump-driven UI automation (windowed mode safe)"""
import subprocess, time, json

TARGET = '127.0.0.1:15566'
HDC = r'"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"'

def sh(cmd, wait=0.3, timeout=60):
    r = subprocess.run(['hdc', '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')

def tap(x, y):
    sh(f'uitest uiInput click {x} {y}')

def activate():
    sh('uitest uiInput keyEvent 2016')

def type_text(x, y, text):
    tap(x, y); activate()
    sh(f"uitest uiInput inputText {x} {y} '{text}'", 0.4)

DUMP_N = 0
def dump():
    global DUMP_N
    DUMP_N += 1
    name = f'e2e_d{DUMP_N}.json'
    sh(f'uitest dumpLayout -p /data/local/tmp/{name}', 1)
    local = rf'D:\BrowserOS - KaihongOS\{name}'
    subprocess.run(['hdc', '-t', TARGET, 'file', 'recv', f'/data/local/tmp/{name}', local], capture_output=True, text=True, timeout=30)
    return json.load(open(local, encoding='utf-8'))

def center(bounds):
    nums = bounds.replace('[', ' ').replace(']', ' ').replace(',', ' ').split()
    return (int(nums[0])+int(nums[2]))//2, (int(nums[1])+int(nums[3]))//2

def find(j, pred):
    if not isinstance(j, dict): return []
    a = j.get('attributes') or {}
    hits = [a] if pred(a) else []
    for c in (j.get('children') or []):
        hits.extend(find(c, pred))
    return hits

def find_one(j, text=None, hint=None, type_=None):
    def p(a):
        if type_ and a.get('type') != type_: return False
        if text is not None and a.get('text', '') != text: return False
        if hint is not None and hint not in (a.get('hint') or ''): return False
        return a.get('bounds', '').count('[') == 2
    hits = find(j, p)
    return center(hits[0]['bounds']) if hits else None

# Step 1: find and click 查看代理 on home dashboard
j = dump()
pos = find_one(j, text='查看代理')
assert pos, '查看代理 not found on screen'
print('查看代理 @', pos)
tap(*pos); time.sleep(2.5)

# Step 2: fill the agent form
j = dump()
name_p = find_one(j, hint='代理名称', type_='TextInput')
url_p = find_one(j, hint='目标URL', type_='TextInput')
task_p = find_one(j, hint='任务描述', type_='TextInput')
create_p = find_one(j, text='创建代理', type_='Button')
print('form:', name_p, url_p, task_p, create_p)
assert all([name_p, url_p, task_p, create_p]), 'form fields incomplete'

type_text(*name_p, 't9')
type_text(*url_p, 'https://example.com')
type_text(*task_p, 'open the page and tell me the page title')
tap(*create_p)
print('=== agent created, watching LLM loop ===')

# Step 3: poll hilog with local filtering
deadline = time.time() + 240
seen_done = False
all_lines = []
while time.time() < deadline:
    time.sleep(25)
    r = subprocess.run(['hdc', '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
    lines = [l for l in (r.stdout or '').splitlines() if any(k in l for k in ('AgentEngine', 'LLMClient', 'BCPEngine'))]
    all_lines = lines
    print('--- poll ---')
    print('\n'.join(lines[-12:]))
    joined = '\n'.join(lines).lower()
    if 'completed' in joined or 'task failed' in joined:
        seen_done = True
        break

sh('snapshot_display -f /data/local/tmp/e2e_final.jpeg', 1)
subprocess.run(['hdc', '-t', TARGET, 'file', 'recv', '/data/local/tmp/e2e_final.jpeg', r'D:\BrowserOS - KaihongOS\e2e_final.jpeg'], capture_output=True, text=True, timeout=30)
print('=== done, seen_done=' + str(seen_done) + ' ===')
