import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\attic"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


# 1) MCP: token 文件在吗？hilog 有 listening 吗？
print('token file:', sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt')[:40])
print('mcp hilog:', sh('hilog -x') .count('MCP-HTTP'), 'MCP-HTTP lines (raw pull below)')
out = sh('hilog -x')
open(EV + r'\api23_hilog.txt', 'w', encoding='utf-8', errors='replace').write(out)
for line in out.splitlines():
    if 'MCP' in line:
        print(' ', line.strip()[:150])
        break

# 2) 图标：冷启动 dump 全部左列 Image + 当前 screenshot 探针
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(7)
sh('uitest dumpLayout -p /data/local/tmp/z.json')
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\api23_v3.json'], capture_output=True, timeout=60)
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\api23_v3.jpeg'], capture_output=True, timeout=60)
lay = open(EV + r'\api23_v3.json', encoding='utf-8', errors='replace').read()
data = json.loads(lay)


def walk(n):
    if isinstance(n, dict):
        a = n.get('attributes')
        if isinstance(a, dict):
            yield a
        for c in (n.get('children') or []):
            yield from walk(c)
    elif isinstance(n, list):
        for c in n:
            yield from walk(c)


win = None
imgs = []
for a in walk(data):
    if a.get('type') == 'ContainerModal' and win is None:
        win = str(a.get('bounds', ''))
    if a.get('type') == 'Image':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and 8 <= (int(m.group(4)) - int(m.group(2))) <= 30:
            imgs.append(b)
print('window:', win)
print('small images:', imgs[:12])
