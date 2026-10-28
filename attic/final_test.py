"""Final device verification: initialize → get session → tools/list → verify."""
import json, subprocess, sys, time, urllib.request
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"


def sh(c):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=30)
    return ((r.stdout or '') + (r.stderr or '')).strip()


token = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip().splitlines()[-1]
print('token:', token[:8] + '...')

# Setup tunnel
subprocess.run([HDC, '-t', T, 'fport', 'rm', 'tcp:19222', 'tcp:9222'], capture_output=True)
subprocess.run([HDC, '-t', T, 'fport', 'tcp:19222', 'tcp:9222'], capture_output=True)
time.sleep(1)

url = 'http://127.0.0.1:19222/mcp?token=' + token

# Step 1: initialize
init_body = json.dumps({
    'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
    'params': {'protocolVersion': '2026-07-28', 'capabilities': {},
               'clientInfo': {'name': 'final-verify', 'version': '1'}}
}).encode()
req = urllib.request.Request(url, data=init_body, headers={'Content-Type': 'application/json'})
with urllib.request.urlopen(req, timeout=10) as resp:
    init_result = json.loads(resp.read().decode())
    session_id = resp.headers.get('Mcp-Session-Id', '')
    print('initialize: protocol=%s server=%s session=%s' % (
        init_result.get('result', {}).get('protocolVersion', '?'),
        init_result.get('result', {}).get('serverInfo', {}).get('name', '?'),
        session_id[:8] + '...' if session_id else 'NONE'))

# Step 2: tools/list with session
list_body = json.dumps({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}}).encode()
req2 = urllib.request.Request(url, data=list_body,
                              headers={'Content-Type': 'application/json', 'Mcp-Session-Id': session_id})
with urllib.request.urlopen(req2, timeout=10) as resp:
    tools_result = json.loads(resp.read().decode())
    tools = tools_result.get('result', {}).get('tools', [])
    names = [t.get('name', '?') for t in tools]
    print('tools/list: %d tools' % len(names))
    print('  names:', names)
    print('  evaluate_in_page:', 'evaluate_in_page' in names)
    print('  evaluate (alias):', 'evaluate' in names)

# Step 3: no session → error
no_sess = json.dumps({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/list', 'params': {}}).encode()
req3 = urllib.request.Request(url, data=no_sess, headers={'Content-Type': 'application/json'})
try:
    with urllib.request.urlopen(req3, timeout=10) as resp:
        err_result = json.loads(resp.read().decode())
        err = err_result.get('error', {})
        print('no-session: code=%s msg=%s' % (err.get('code'), err.get('message', '')[:50]))
except Exception as e:
    print('no-session error: %s' % str(e)[:60])

print('\nFINAL VERIFICATION COMPLETE')
