"""P40-B diag2: real token raw initialize response + check restart side."""
import json, socket, subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"

def sh(c, tmo=60):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

tok = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip()
print('token:', repr(tok))
body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}).encode()
s = socket.create_connection(("192.168.161.137", 9222), timeout=10)
req = ("POST /mcp?token=" + tok + " HTTP/1.1\r\nHost: h\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " + str(len(body)) + "\r\n\r\n").encode() + body
s.sendall(req)
d = b''
try:
    while True:
        c = s.recv(65536)
        if not c:
            break
        d += c
except Exception as e:
    print('recv end:', e)
s.close()
text = d.decode('utf-8', 'replace')
print('raw len:', len(text))
print(text[:1200])
