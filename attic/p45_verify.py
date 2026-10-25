"""P45 proper close-button test: re-dump between each click."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p45"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump():
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\verify.json'],
                   capture_output=True, timeout=60)
    return open(EV + r'\verify.json', encoding='utf-8', errors='replace').read()


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


def count_tabs(lay):
    """Count tab rows by finding text nodes in left column that look like tab titles."""
    tabs = []
    for a in walk(json.loads(lay)):
        t = a.get('text') or ''
        if t in ('about:blank', '新标签页') or (len(t) > 3 and a.get('type') == 'Text'):
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m and int(m.group(1)) < 200 and int(m.group(3)) < 300:
                tabs.append(int(m.group(2)))
    return len(tabs), sorted(tabs)


def find_close_btns(lay):
    """Find close buttons: Button in left column, x>150 (right side of tab row), y<300."""
    closes = []
    for a in walk(json.loads(lay)):
        if a.get('type') == 'Button':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                x1, y1, x2, y2 = map(int, m.groups())
                if x1 > 100 and x2 <= 500 and y1 < 400 and 'Enhance' not in str(a.get('id', '')):
                    closes.append((y1, b))
    closes.sort()
    return closes


def find_plus(lay):
    """Find + button: Button in left column, x<100, y<400 (now near tabs)."""
    for a in walk(json.loads(lay)):
        if a.get('type') == 'Button':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                x1, y1, x2, y2 = map(int, m.groups())
                if x1 < 100 and x2 <= 200 and y1 < 400 and 'Enhance' not in str(a.get('id', '')):
                    return b
    return None


# 冷启动
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)

print('=== Step 1: + button position check ===')
lay = dump()
plus = find_plus(lay)
n, ys = count_tabs(lay)
print('tabs:', n, 'at y positions:', ys)
if plus:
    py = int(re.findall(r'\d+', plus)[1])
    print('plus button:', plus, '→ y=%d' % py)
    if ys:
        last_tab_y = ys[-1]
        gap = py - last_tab_y
        print('last tab at y=%d, gap=%d → %s' % (last_tab_y, gap, 'CORRECT (right below)' if 0 < gap < 80 else 'WRONG'))
else:
    print('plus not found in tab area')

print('\n=== Step 2: + adds tabs ===')
for i in range(2):
    lay = dump()
    plus = find_plus(lay)
    if plus:
        xs = [int(v) for v in re.findall(r'\d+', plus)]
        sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))
        time.sleep(2)
lay = dump()
n_after, _ = count_tabs(lay)
print('after 2 + clicks: %d tabs' % n_after)

print('\n=== Step 3: × closes tabs (fresh dump each time) ===')
for attempt in range(2):
    lay = dump()
    closes = find_close_btns(lay)
    n_before, _ = count_tabs(lay)
    if not closes:
        print('attempt %d: no close buttons found' % (attempt + 1))
        break
    btn = closes[0][1]  # topmost close
    xs = [int(v) for v in re.findall(r'\d+', btn)]
    print('attempt %d: clicking close at %s (tabs=%d)' % (attempt + 1, btn, n_before))
    sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))
    time.sleep(2)
    lay2 = dump()
    n_after2, _ = count_tabs(lay2)
    result = 'WORKS' if n_after2 == n_before - 1 else 'FAILED (%d→%d)' % (n_before, n_after2)
    print('  result: %d → %d = %s' % (n_before, n_after2, result))

print('\nDONE')
