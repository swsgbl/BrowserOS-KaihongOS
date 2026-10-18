"""P37: open menu, pixel-probe the icon column left of menu item texts."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p37"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


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


lay = open(EV + r'\fix.json', encoding='utf-8', errors='replace').read()
data = json.loads(lay)
# ⋮ = 工具栏最右钮
best, mb = -1, None
for a in walk(data):
    if a.get('type') != 'Button':
        continue
    b = str(a.get('bounds', ''))
    m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if y1 < 60 or y1 > 400 or x1 < 900 or 'Enhance' in str(a.get('id', '')):
        continue
    if x2 > best:
        best, mb = x2, m.groups()
xs = [int(v) for v in mb]
sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))
time.sleep(2.5)
sh('uitest dumpLayout -p /data/local/tmp/z.json')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\menu.json'],
               capture_output=True, timeout=60)
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\menu.jpeg'],
               capture_output=True, timeout=60)
lay = open(EV + r'\menu.json', encoding='utf-8', errors='replace').read()
data = json.loads(lay)
items = []
for a in walk(data):
    t = a.get('text') or ''
    if t in ('新建标签页', '历史', '书签', '下载', '定时任务', 'Skills', '设置', '查找', '帮助', '退出'):
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m:
            items.append((t, list(map(int, m.groups()))))
print('menu items:', [(t, b) for t, b in items[:6]])
# 图标在文字左侧 ~20px 处
for t, b in items[:4]:
    print('%s icon region: [%d,%d][%d,%d]' % (t, b[0] - 26, b[1], b[0] - 6, b[3]))
