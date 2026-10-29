#!/usr/bin/env python3
"""P68-B: snapshot transitional settle (the gap this stick closed) + executeJS 100x timer stress."""
import json, subprocess, sys, time, urllib.request, urllib.error
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
HOST_PORT = 19222

def sh(cmd, tmo=60):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()

SESSION = [None]

def http_post(path_qs, body, timeout=15, session=None):
    headers = {'Content-Type': 'application/json'}
    if session: headers['Mcp-Session-Id'] = session
    req = urllib.request.Request('http://127.0.0.1:%d%s' % (HOST_PORT, path_qs), data=json.dumps(body).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            sid = resp.headers.get('Mcp-Session-Id')
            if sid: SESSION[0] = sid
            raw = resp.read().decode()
            try: return resp.status, json.loads(raw) if raw.strip() else {}
            except Exception: return resp.status, {}
    except urllib.error.HTTPError as e:
        try: return e.code, json.loads(e.read().decode())
        except Exception: return e.code, {}

_id = [0]
def rpc(method, params):
    _id[0] += 1
    return {'jsonrpc': '2.0', 'id': _id[0], 'method': method, 'params': params}

def tool_text(resp):
    try:
        txt = resp['result']['content'][0]['text']
        try: return json.loads(txt)
        except Exception: return txt
    except Exception: return {}

token = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip().splitlines()[-1]
qs = '/mcp?token=' + token
code, init = http_post(qs, rpc('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {}, 'clientInfo': {'name': 'p68b', 'version': '1'}}))
assert code == 200
http_post(qs, {'jsonrpc': '2.0', 'method': 'notifications/initialized'}, session=SESSION[0])

def call(name, args):
    return http_post(qs, rpc('tools/call', {'name': name, 'arguments': args}), session=SESSION[0])

results = []
def record(name, ok, detail=''):
    results.append(ok)
    print(('[PASS] ' if ok else '[FAIL] ') + name + ((' — ' + detail) if detail else ''))

# B1: snapshot right after navigate (inside 3s window) must not return empty content
code, r = call('tabs', {'action': 'new'})
d = tool_text(r); tid = d.get('tabId', '')
code, _ = call('navigate', {'url': 'https://example.com', 'tabId': tid})
time.sleep(0.3)
code, r = call('snapshot', {'tabId': tid})
d = tool_text(r)
content = d.get('content', '') if isinstance(d, dict) else ''
ok = code == 200 and isinstance(content, str) and len(content.strip()) > 0 and content.strip() not in ('null', 'undefined')
record('snapshot right after navigate -> non-empty content', ok, ('len=%d head=%r' % (len(content), content[:60])) if isinstance(content, str) else str(d)[:100])

# B2: executeJS 100x stress — all fast, no error growth (orphan-timer leak would show timeouts)
t0 = time.time(); fails = 0
for i in range(100):
    code, r = call('evaluate_in_page', {'expression': '1+1'})
    dd = tool_text(r)
    if not (code == 200 and isinstance(dd, dict) and '2' in str(dd.get('result', ''))):
        fails += 1
dt = time.time() - t0
record('100x evaluate stress (timer-leak check)', fails == 0 and dt < 60, 'fails=%d dt=%.1fs' % (fails, dt))

call('tabs', {'action': 'close', 'tabId': tid})
print('\n== p68_b_verify: %d/%d PASS ==' % (sum(1 for x in results if x), len(results)))
sys.exit(0 if all(results) else 1)
