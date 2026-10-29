#!/usr/bin/env python3
"""P67 regression: agent_register + device_agent_tasks loop over MCP (no UI code touched this stick)."""
import json, subprocess, sys, urllib.request, urllib.error
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
def rpc(m, p):
    _id[0] += 1
    return {'jsonrpc': '2.0', 'id': _id[0], 'method': m, 'params': p}

def tool_text(resp):
    try:
        txt = resp['result']['content'][0]['text']
        try: return json.loads(txt)
        except Exception: return txt
    except Exception: return {}

token = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip().splitlines()[-1]
qs = '/mcp?token=' + token
code, _ = http_post(qs, rpc('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {}, 'clientInfo': {'name': 'p68-p67regr', 'version': '1'}}))
assert code == 200
http_post(qs, {'jsonrpc': '2.0', 'method': 'notifications/initialized'}, session=SESSION[0])

def call(name, args):
    return http_post(qs, rpc('tools/call', {'name': name, 'arguments': args}), session=SESSION[0])

results = []
def record(n, ok, d=''):
    results.append(ok)
    print(('[PASS] ' if ok else '[FAIL] ') + n + ((' — ' + d) if d else ''))

# tools/list must expose the P67 pair + P65 pair (21 total)
code, r = http_post(qs, rpc('tools/list', {}), session=SESSION[0])
names = [t['name'] for t in r.get('result', {}).get('tools', [])]
record('tools/list has 21 tools incl P67 pair', len(names) == 21 and 'agent_register' in names and 'device_agent_tasks' in names, 'n=%d' % len(names))

# register heartbeat
code, r = call('agent_register', {'name': 'claude-code', 'kind': 'claude-code'})
d = tool_text(r)
record('agent_register claude-code', isinstance(d, dict) and d.get('name') == 'claude-code', str(d)[:80])

# inbox next (no task pending is fine — hasTask flag must be present)
code, r = call('device_agent_tasks', {'action': 'next', 'agent': 'claude-code'})
d = tool_text(r)
record('device_agent_tasks next responds', isinstance(d, dict) and 'hasTask' in d, str(d)[:80])

# complete on bogus id -> explicit error
code, r = call('device_agent_tasks', {'action': 'complete', 'taskId': 'bogus_zzz', 'ok': True, 'result': 'x'})
ok = code == 200 and ('error' in json.dumps(r) and 'not found' in json.dumps(r))
record('complete bogus id -> explicit error', ok, json.dumps(r.get('error', {}))[:80] if 'error' in r else str(tool_text(r))[:80])

print('\n== p67_regression: %d/%d PASS ==' % (sum(1 for x in results if x), len(results)))
sys.exit(0 if all(results) else 1)
