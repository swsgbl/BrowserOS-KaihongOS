"""P45: click ACTUAL tab close buttons (x=163-195, inside 200px strip)."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump():
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', r'D:\BrowserOS - KaihongOS\evidence\p45\close2.json'],
                   capture_output=True, timeout=60)
    return open(r'D:\BrowserOS - KaihongOS\evidence\p45\close2.json', encoding='utf-8', errors='replace').read()


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


def tab_closes(lay):
    """Strict: Button with x2 <= 200 (inside tab strip), x1 > 120, y < 400."""
    r = []
    for a in walk(json.loads(lay)):
        if a.get('type') == 'Button':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                x1, y1, x2, y2 = map(int, m.groups())
                if 120 < x1 and x2 <= 200 and 30 < y1 < 400:
                    r.append((y1, b))
    r.sort()
    return r


def count_tabs(lay):
    n = 0
    for a in walk(json.loads(lay)):
        t = a.get('text') or ''
        if t and len(t) > 2:
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m and int(m.group(1)) < 120 and 30 < int(m.group(2)) < 400:
                n += 1
    return n


for round_num in range(3):
    lay = dump()
    closes = tab_closes(lay)
    n = count_tabs(lay)
    if not closes:
        print('round %d: no tab close buttons found' % (round_num + 1))
        break
    btn = closes[0][1]  # topmost tab close
    xs = [int(v) for v in re.findall(r'\d+', btn)]
    cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
    print('round %d: clicking tab close %s center=(%d,%d), tabs=%d, closes=%d' % (round_num + 1, btn, cx, cy, n, len(closes)))
    sh('uitest uiInput click %d %d' % (cx, cy))
    time.sleep(2)
    # hilog check
    h = sh('hilog -x')
    p45 = [l for l in h.splitlines() if 'P45' in l]
    for l in p45[-2:]:
        print('  HILOG:', l.strip()[:100])
    if not p45:
        print('  (no [P45] log found)')
    lay2 = dump()
    n2 = count_tabs(lay2)
    print('  result: %d → %d = %s' % (n, n2, 'WORKS ✓' if n2 == n - 1 else 'FAILED ✗'))
