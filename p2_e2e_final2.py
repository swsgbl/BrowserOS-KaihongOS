# -*- coding: utf-8 -*-
"""Final P2 e2e: retry-forever UI strike + differential https/ollama test"""
import subprocess, time, json, sys

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
    sh('uitest dumpLayout -p /data/local/tmp/strike.json', 1)
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/strike.json', r'D:\BrowserOS - KaihongOS\strike.json'], capture_output=True, timeout=30)
    return json.load(open(r'D:\BrowserOS - KaihongOS\strike.json', encoding='utf-8'))

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

def get_logs():
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
    return [l for l in (r.stdout or '').splitlines() if ('LLMClient' in l or 'AgentEngine' in l or 'BCPEngine' in l)]

def strike_agent(label, url_value, task_value):
    """One attempt: bring app front, navigate to form, fill, create. Returns True if task started."""
    sh('aa start -a EntryAbility -b com.browseros.kaihong', 2)
    j = dump()
    home_btn = find_one(j, text='查看代理')
    if not home_btn:
        return False
    tap(*home_btn); time.sleep(2)
    j = dump()
    f = {k: find_one(j, hint=h, type_='TextInput') for k, h in (('name','代理名称'),('url','目标URL'),('task','任务描述'))}
    f['create'] = find_one(j, text='创建代理', type_='Button')
    if not all(f.values()):
        return False
    type_text(*f['name'], label)
    type_text(*f['url'], url_value)
    type_text(*f['task'], task_value)
    sh('hilog -r', 0.5)
    tap(*f['create'])
    time.sleep(8)
    logs = get_logs()
    started = any('task start' in l for l in logs)
    print(f'--- {label}: started={started} ---', flush=True)
    for l in logs[:10]:
        print(l, flush=True)
    return started

# ---- Phase A: differential test (https endpoint currently configured) ----
print('=== Phase A: https differential (config=example.com) ===', flush=True)
okA = False
for i in range(12):
    if strike_agent('httpsT', 'https://example.com', 'hi'):
        okA = True
        break
    time.sleep(15)
print('PhaseA result:', okA, flush=True)

# Phase A logs already show whether HTTPS got HTTP status vs instant fail
time.sleep(3)
logs = get_logs()
https_lines = [l for l in logs if 'LLMClient' in l]
print('=== Phase A LLMClient lines ===', flush=True)
print('\n'.join(https_lines[-8:]) or '(none)', flush=True)

# ---- Phase B: switch config to ollama 11435 and run real e2e ----
print('=== Phase B: pushing ollama config ===', flush=True)
cfg = open(r'D:\BrowserOS - KaihongOS\.zcode\clean-config2.json', encoding='utf-8').read() if __import__('os').path.exists(r'D:\BrowserOS - KaihongOS\.zcode\clean-config2.json') else None
import os
sh('aa force-stop com.browseros.kaihong', 1)
subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'send', r'D:\BrowserOS - KaihongOS\.zcode\clean-config2.json', '/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json'], capture_output=True, timeout=30)
sh('aa start -a EntryAbility -b com.browseros.kaihong', 2)

okB = False
for i in range(12):
    if strike_agent('e2e', 'https://example.com', 'open the page and tell me the page title'):
        okB = True
        break
    time.sleep(15)
print('PhaseB created:', okB, flush=True)

# ---- watch loop ----
end = time.time() + 420
seen = False
while time.time() < end:
    time.sleep(25)
    logs = get_logs()
    print('--- watch ' + time.strftime('%H:%M:%S') + ' ---', flush=True)
    print('\n'.join(logs[-12:]) or '(quiet)', flush=True)
    joined = '\n'.join(logs).lower()
    if 'completed' in joined or 'task failed' in joined:
        seen = True
        break

sh('snapshot_display -f /data/local/tmp/e2e_last.jpeg', 1)
subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/e2e_last.jpeg', r'D:\BrowserOS - KaihongOS\e2e_last.jpeg'], capture_output=True, timeout=30)
print(f'=== FINAL: A={okA} B={okB} seen_done={seen} ===', flush=True)
