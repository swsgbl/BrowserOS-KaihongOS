"""P45 close-button test with CORRECT tab strip bounds (x < 200)."""
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
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\close_test.json'],
                   capture_output=True, timeout=60)
    return open(EV + r'\close_test.json', encoding='utf-8', errors='replace').read()


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


def tab_close_buttons(lay):
    """Tab close = Button with x1 > 130, x2 <= 210 (inside 200px tab strip, right side)."""
    closes = []
    for a in walk(json.loads(lay)):
        if a.get('type') == 'Button':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                x1, y1, x2, y2 = map(int, m.groups())
                if 130 < x1 < 210 and y1 > 30 and y1 < 400:
                    closes.append((y1, b, a.get('accessibilityText', '')))
    closes.sort()
    return closes


def tab_count(lay):
    """Count tab title texts in left column."""
    n = 0
    for a in walk(json.loads(lay)):
        t = a.get('text') or ''
        if t and len(t) > 2:
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m and int(m.group(1)) < 130 and 30 < int(m.group(2)) < 400:
                n += 1
    return n


sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)

lay = dump()
closes = tab_close_buttons(lay)
n0 = tab_count(lay)
print('tabs=%d, close buttons found=%d' % (n0, len(closes)))
for y, b, a11y in closes[:5]:
    print('  close@y=%d %s a11y=%r' % (y, b, a11y[:30]))

# 逐个关（每次重新 dump）
for i in range(min(3, len(closes))):
    lay = dump()
    closes_now = tab_close_buttons(lay)
    n_before = tab_count(lay)
    if not closes_now:
        print('round %d: no close buttons' % (i + 1))
        break
    btn = closes_now[0][1]  # topmost
    xs = [int(v) for v in re.findall(r'\d+', btn)]
    cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
    print('round %d: clicking %s center=(%d,%d), tabs=%d' % (i + 1, btn, cx, cy, n_before))
    sh('uitest uiInput click %d %d' % (cx, cy))
    time.sleep(2)
    # 检查 hilog
    h = sh('hilog -x')
    hit = [l for l in h.splitlines() if 'P45' in l and 'close' in l.lower()]
    for l in hit[-2:]:
        print('  HILOG:', l.strip()[:100])
    lay2 = dump()
    n_after = tab_count(lay2)
    ok = 'WORKS' if n_after == n_before - 1 else 'FAILED'
    print('  result: %d → %d = %s' % (n_before, n_after, ok))
