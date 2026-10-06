# -*- coding: utf-8 -*-
"""P7 final walkthrough: replay visual + onboarding + confirm dialog"""
import subprocess, time, json
TARGET = '127.0.0.1:15566'
HDC_EXE = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
def sh(cmd, wait=0.3, timeout=60):
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    time.sleep(wait)
    return (r.stdout or '') + (r.stderr or '')
def tap(x, y): sh(f'uitest uiInput click {x} {y}')
def dump():
    sh('uitest dumpLayout -p /data/local/tmp/p7w.json', 0.8)
    subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/p7w.json', r'D:\BrowserOS - KaihongOS\p7w.json'], capture_output=True, timeout=30)
    return json.load(open(r'D:\BrowserOS - KaihongOS\p7w.json', encoding='utf-8'))
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
    def center(h):
        n = h['bounds'].replace('[',' ').replace(']',' ').replace(',',' ').split()
        return (int(n[0])+int(n[2]))//2, (int(n[1])+int(n[3]))//2
    return center(hits[0]) if hits else None

# --- 1. Replay visual ---
sh('hilog -r', 0.5)
sh('aa start -a EntryAbility -b com.browseros.kaihong', 2)
j = dump()
agents_btn = find_one(j, text='查看代理')
if agents_btn:
    tap(*agents_btn); time.sleep(2)
    j = dump()
    replay = find_one(j, text='回放')
    if replay:
        tap(*replay); time.sleep(4)
        sh('snapshot_display -f /data/local/tmp/w_replay.jpeg', 1)
        subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/w_replay.jpeg', r'D:\BrowserOS - KaihongOS\w_replay.jpeg'], capture_output=True, timeout=30)
        print('replay screenshot taken', flush=True)
    else:
        print('no replay button (maybe no session list entry)', flush=True)

# --- 2. Onboarding trigger ---
sh('aa force-stop com.browseros.kaihong', 1)
sh("sed -i 's/\"isOnboardingCompleted\":true/\"isOnboardingCompleted\":false/' /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json", 0.5)
sh('aa start -a EntryAbility -b com.browseros.kaihong', 4)
r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
ob = [l for l in (r.stdout or '').splitlines() if 'nboarding' in l or 'Onboarding' in l]
print('=== onboarding logs ===', flush=True)
print('\n'.join(ob[-6:]) or '(none)', flush=True)
sh('snapshot_display -f /data/local/tmp/w_onboard.jpeg', 1)
subprocess.run([HDC_EXE, '-t', TARGET, 'file', 'recv', '/data/local/tmp/w_onboard.jpeg', r'D:\BrowserOS - KaihongOS\w_onboard.jpeg'], capture_output=True, timeout=30)
# restore config
sh('aa force-stop com.browseros.kaihong', 1)
sh("sed -i 's/\"isOnboardingCompleted\":false/\"isOnboardingCompleted\":true/' /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json", 0.5)

# --- 3. ConfirmDialog: navigate to a sensitive URL via address bar is unreliable; use BCP via MCP instead ---
# Use MCP tools/call navigate to a pay-keyword URL to trigger SensitiveOperationDetector
import urllib.request
def mcp_call(name, args):
    tok = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt'], capture_output=True, text=True, timeout=30).stdout.strip()
    body = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': name, 'arguments': args}}).encode()
    req = urllib.request.Request(f'http://127.0.0.1:9222/mcp?token={tok}', data=body, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.read().decode()[:200]
    except Exception as e:
        return f'ERR {e}'
print('mcp navigate pay-url:', mcp_call('navigate', {'url': 'https://pay.example-checkout.com/pay'}), flush=True)
time.sleep(3)
r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
sd = [l for l in (r.stdout or '').splitlines() if 'ensitive' in l or 'Confirm' in l]
print('=== sensitive/confirm logs ===', flush=True)
print('\n'.join(sd[-8:]) or '(none)', flush=True)
j = dump()
confirm = find_one(j, text='确认') or find_one(j, hint='确认')
print('confirm dialog present:', confirm, flush=True)
if confirm:
    tap(*confirm); time.sleep(1)
    r = subprocess.run([HDC_EXE, '-t', TARGET, 'shell', 'hilog -x'], capture_output=True, text=True, timeout=60)
    rs = [l for l in (r.stdout or '').splitlines() if 'resolve' in l.lower() or 'CONFIRMED' in l or 'confirm' in l.lower()]
    print('after confirm:', '\n'.join(rs[-4:]) or '(none)', flush=True)
print('=== WALKTHROUGH DONE ===', flush=True)
