# -*- coding: utf-8 -*-
"""P2 e2e final: navigate to NeoDashboard, create agent, watch LLM loop"""
import subprocess, time, json

TARGET = '127.0.0.1:15566'

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

def dump(name):
    sh(f'uitest dumpLayout -p /data/local/tmp/{name}', 1)
    subprocess.run(['hdc', '-t', TARGET, 'file', 'recv', f'/data/local/tmp/{name}', f'D:\\BrowserOS - KaihongOS\\{name}'], capture_output=True, text=True, timeout=30)

# 1. app is at BrowserShell home -> click 查看代理
tap(801, 336); time.sleep(2.5)
dump('e2e_p1.json')

# parse form coords from dump
layout = json.load(open(r'D:\BrowserOS - KaihongOS\e2e_p1.json', encoding='utf-8'))
fields = {}
def walk(n):
    if not isinstance(n, dict): return
    a = n.get('attributes') or {}
    m = (a.get('bounds') or '').replace('[',' ').replace(']',' ').split()
    if len(m) == 4 and a.get('type') == 'TextInput':
        hint = (a.get('hint') or '')
        cx, cy = (int(m[0])+int(m[2]))//2, (int(m[1])+int(m[3]))//2
        if '名称' in hint: fields['name'] = (cx, cy)
        elif 'URL' in hint: fields['url'] = (cx, cy)
        elif '描述' in hint or '任务' in hint: fields['task'] = (cx, cy)
    if len(m) == 4 and a.get('type') == 'Button' and a.get('text') == '创建代理':
        fields['create'] = ((int(m[0])+int(m[2]))//2, (int(m[1])+int(m[3]))//2)
    for c in (n.get('children') or []): walk(c)
walk(layout)
print('fields:', fields)
assert all(k in fields for k in ('name','url','task','create')), 'form fields not found'

# 2. fill and create
type_text(*fields['name'], 't9')
type_text(*fields['url'], 'https://example.com')
type_text(*fields['task'], 'open the page and tell me the page title')
tap(*fields['create'])
print('=== agent created, watching LLM loop ===')

# 3. poll hilog via local filter (pipe not allowed in hdc shell quoting here)
deadline = time.time() + 200
seen_done = False
while time.time() < deadline:
    time.sleep(20)
    r = subprocess.run(['hdc', '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
    lines = [l for l in (r.stdout or '').splitlines() if ('AgentEngine' in l or 'LLMClient' in l or 'BCPEngine' in l)]
    print('--- poll ---')
    print('\n'.join(lines[-12:]))
    joined = '\n'.join(lines).lower()
    if 'completed' in joined or 'task failed' in joined:
        seen_done = True
        break

sh('snapshot_display -f /data/local/tmp/e2e_final.jpeg', 1)
subprocess.run(['hdc', '-t', TARGET, 'file', 'recv', '/data/local/tmp/e2e_final.jpeg', r'D:\BrowserOS - KaihongOS\e2e_final.jpeg'], capture_output=True, text=True, timeout=30)
print('=== done, seen_done=' + str(seen_done) + ' ===')
