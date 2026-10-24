"""P40-B: push the REAL new build (entry-api23-unsigned.hap with instructions), sign, install, verify."""
import json, socket, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
HAP = r"D:\BrowserOS - KaihongOS\entry-api23-unsigned.hap"

def sh(c, tmo=120):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

r = subprocess.run([HDC, '-t', T, 'file', 'send', HAP, '/data/local/tmp/x.hap'], capture_output=True, text=True, timeout=180, encoding='utf-8', errors='replace')
print('send:', (r.stdout or r.stderr).strip())
SIGN = ("/data/local/home/.local/bin/hap-sign-tool sign-app -keyAlias 'OpenHarmony Application Release' "
        "-signAlg SHA256withECDSA -mode localSign "
        "-appCertFile /data/local/home/.ohos/signature/OpenHarmonyApplication.pem "
        "-profileFile /data/local/home/.ohos/signature/browseros-profile-release.p7b "
        "-inFile /data/local/tmp/x.hap -outFile /data/local/tmp/x_signed.hap "
        "-keystoreFile /data/local/home/.ohos/signature/OpenHarmony.p12 -keyPwd 123456 -keystorePwd 123456 -compatibleVersion 23")
print('sign:', sh(SIGN, tmo=120)[-120:])
print('install:', sh('bm install -p /data/local/tmp/x_signed.hap -r', tmo=120)[-200:])
time.sleep(1)
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)
tok = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip()
print('token:', repr(tok[:6]) + '...')
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
print(text[:400])
i = text.find('{')
obj = json.loads(text[i:]) if i >= 0 else {}
res = obj.get('result', {})
print('instructions present:', 'instructions' in res)
ins = res.get('instructions', '')
print('len:', len(ins), '| Preserve useful pages:', 'Preserve useful pages' in ins, '| tab group:', "tab group" in ins)
