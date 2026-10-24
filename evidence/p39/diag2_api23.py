import json, re, subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"


def sh(c, tmo=60):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def raw(args, tmo=60):
    r = subprocess.run([HDC, '-t', T] + args, capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


# 1) fport 清理重建
print('fport ls before:', raw(['fport', 'ls']).replace('\n', ' | ')[:200])
raw(['fport', 'rm', 'tcp:9222', 'tcp:9222'])
print('fport add:', raw(['fport', 'tcp:9222', 'tcp:9222'])[:80])
import urllib.request
tok = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip().splitlines()[-1]
body = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
                   'params': {'protocolVersion': '2024-11-05', 'capabilities': {},
                              'clientInfo': {'name': 'p39diag', 'version': '1'}}}).encode()
req = urllib.request.Request('http://127.0.0.1:9222/mcp?token=' + tok, data=body,
                             headers={'Content-Type': 'application/json'})
try:
    with urllib.request.urlopen(req, timeout=8) as resp:
        print('MCP init:', resp.status, resp.read()[:80])
except Exception as e:
    print('MCP init FAIL:', str(e)[:120])

# 2) 图标像素（api23_v3.jpeg 上真实坐标）
from PIL import Image
im = Image.open(r'D:\BrowserOS - KaihongOS\attic\api23_v3.jpeg').convert('L')
for name, box in [('favicon', (226, 187, 238, 199)), ('toolbar1', (427, 183, 447, 203)),
                  ('toolbar2', (463, 183, 483, 203)), ('toolbar_right', (960, 183, 980, 203))]:
    px = list(im.crop(box).getdata())
    bg = max(set(px), key=px.count)
    nonbg = sum(1 for v in px if abs(v - bg) > 25)
    print('%s %s non-bg %.1f%%' % (name, box, 100.0 * nonbg / len(px)))
