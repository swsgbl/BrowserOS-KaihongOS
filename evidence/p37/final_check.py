"""P37 final check: fresh dump -> locate strip buttons -> ASCII render strip."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p37"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
sh('uitest dumpLayout -p /data/local/tmp/z.json')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\v2.json'],
               capture_output=True, timeout=60)
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\v2.jpeg'],
               capture_output=True, timeout=60)
lay = open(EV + r'\v2.json', encoding='utf-8', errors='replace').read()
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


cands = []
for a in walk(data):
    if a.get('type') == 'Button':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if x2 <= 450 and 'Enhance' not in str(a.get('id', '')):
            cands.append((y1, x1, b))
cands.sort()
print('strip buttons:', cands)
# 窗口内容区
win = None
for a in walk(data):
    if a.get('type') == 'ContainerModal':
        win = str(a.get('bounds', ''))
        break
print('window:', win)
