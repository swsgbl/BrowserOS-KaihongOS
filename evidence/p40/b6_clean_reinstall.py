"""P40-B diag5: device abc stale — WHEN was device hap installed? force-clean reinstall.
The bm install -r may have kept the old abc (signature/provisioning match?). Reinstall cleanly."""
import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"

def sh(c, tmo=120):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

# 1. uninstall fully
print('uninstall:', sh('bm uninstall -n com.browseros.kaihong'))
time.sleep(2)
# 2. install signed hap again
print('install:', sh('bm install -p /data/local/tmp/x_signed.hap'))
time.sleep(2)
# 3. launch & check instructions via fresh token file
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)
tok = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip()
print('token:', repr(tok))
import json, socket
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
except Exception:
    pass
s.close()
text = d.decode('utf-8', 'replace')
print(text[:900])
print('instructions present:', '"instructions"' in text)
