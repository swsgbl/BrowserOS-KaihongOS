"""P40-B: verify MCP initialize instructions — read token from device filesDir first."""
import json, socket, subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"

def sh(c, tmo=60):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

# token persisted to files el2 under mcp_token.txt — find it
tok = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt 2>/dev/null')
print('token:', repr(tok[:8]) + '...' if tok else 'NOT FOUND, trying el1')
if not tok:
    tok = sh('cat /data/storage/el2/base/haps/entry/files/mcp_token.txt 2>/dev/null')
    print('el1:', repr(tok[:8]) if tok else 'no')
if not tok:
    # search
    print(sh('find /data -name mcp_token.txt 2>/dev/null | head -n 3'))
    tok = sh('cat $(find /data -name mcp_token.txt 2>/dev/null | head -n 1) 2>/dev/null')
if not tok:
    print('no token; abort')
    sys.exit(1)
tok = tok.strip()

body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}).encode()
req = ("POST /mcp?token=" + tok + " HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: ").encode() + str(len(body)).encode() + b"\r\n\r\n" + body
s = socket.create_connection(("192.168.161.137", 9222), timeout=10)
s.sendall(req)
data = b''
while True:
    try:
        chunk = s.recv(65536)
    except Exception:
        break
    if not chunk:
        break
    data += chunk
s.close()
text = data.decode('utf-8', errors='replace')
print('HTTP status:', text.splitlines()[0] if text else 'EMPTY')
i = text.find('{')
obj = json.loads(text[i:]) if i >= 0 else {}
res = obj.get('result', {})
print('instructions present:', 'instructions' in res)
ins = res.get('instructions', '')
print('instructions len:', len(ins))
for k in ("Preserve useful pages", "tab group"):
    print('contains %r:' % k, k in ins)
print('--- first 300 chars:')
print(ins[:300])
