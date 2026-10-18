"""P37 atomic: SAME boot -> dump -> locate strip buttons -> snapshot -> probe those exact bounds."""
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
time.sleep(7)
# dump + screenshot 背靠背（同一秒级窗口）
sh('uitest dumpLayout -p /data/local/tmp/z.json')
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\atomic.json'],
               capture_output=True, timeout=60)
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\atomic.jpeg'],
               capture_output=True, timeout=60)

lay = open(EV + r'\atomic.json', encoding='utf-8', errors='replace').read()
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


btns = []
win = None
for a in walk(data):
    if a.get('type') == 'ContainerModal' and win is None:
        win = str(a.get('bounds', ''))
    if a.get('type') == 'Button':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and int(m.group(3)) <= 450 and 'Enhance' not in str(a.get('id', '')):
            btns.append((int(m.group(2)), int(m.group(1)), b, a.get('accessibilityText', '')))
btns.sort()
print('window:', win)
print('strip buttons (y,x,accessibility):')
for y, x, b, a11y in btns:
    print(' ', b, repr(a11y))
# 输出 Image 节点（图标本体若渲染，其 Image bounds 应在按钮内）
imgs = []
for a in walk(data):
    if a.get('type') == 'Image':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and int(m.group(3)) <= 450 and int(m.group(2)) > 150:
            imgs.append(b)
print('left-col Image nodes:', imgs[:8])
