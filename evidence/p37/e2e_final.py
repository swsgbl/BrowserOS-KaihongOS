"""P37 final E2E: atomic coords — click + (tab+1), click x (tab-1); menu icon check."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p37"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump(name):
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + '\\' + name],
                   capture_output=True, timeout=60)
    return open(EV + '\\' + name, encoding='utf-8', errors='replace').read()


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


def strip_buttons(lay):
    btns = []
    for a in walk(json.loads(lay)):
        if a.get('type') == 'Button':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m and int(m.group(3)) <= 450 and 'Enhance' not in str(a.get('id', '')):
                btns.append((int(m.group(2)), int(m.group(1)), b))
    btns.sort()
    return btns


def click(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))


def tabs_now():
    out = sh('hilog -x | grep managerTabs | tail -1')
    m = re.findall(r'managerTabs=(\d+)', out)
    return int(m[-1]) if m else None


lay = dump('e2e0.json')
btns = strip_buttons(lay)
print('buttons:', [(b[1], b[0], b[2]) for b in btns])
close_b = btns[0][2] if btns else None
plus_b = btns[-2][2] if len(btns) >= 2 else None
n0 = tabs_now()
print('tabs:', n0, 'plus:', plus_b, 'close:', close_b)
if plus_b:
    click(plus_b)
    time.sleep(2)
    n1 = tabs_now()
    print('after + :', n1, '=>', 'PASS' if n1 == (n0 or 0) + 1 else 'FAIL')
if close_b:
    click(close_b)
    time.sleep(2)
    n2 = tabs_now()
    print('after x :', n2, '=>', 'PASS' if n2 == (n1 or 0) - 1 else 'FAIL')

# 菜单图标检查（$r 体系）：点 ⋮ -> 找 历史 文本 bounds -> 其左侧 Image bounds 输出
lay2 = dump('e2e1.json')
best, mb = -1, None
for a in walk(json.loads(lay2)):
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
if mb:
    xs = [int(v) for v in mb]
    sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))
    time.sleep(2.5)
    lay3 = dump('e2e_menu.json')
    data3 = json.loads(lay3)
    hist = None
    for a in walk(data3):
        if (a.get('text') or '') == '历史':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                hist = list(map(int, m.groups()))
                break
    print('menu 历史 bounds:', hist)
    if hist:
        # 图标 Image 在文字左侧
        for a in walk(data3):
            if a.get('type') == 'Image':
                b = str(a.get('bounds', ''))
                m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
                if m:
                    x1, y1, x2, y2 = map(int, m.groups())
                    if hist[1] - 4 <= y1 <= hist[3] and x2 <= hist[0]:
                        print('menu history icon Image bounds:', b)
    sh('snapshot_display -f /data/local/tmp/z.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\e2e_menu.jpeg'],
                   capture_output=True, timeout=60)
