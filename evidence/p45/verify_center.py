"""Verify + button is horizontally centered after fix."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump():
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json',
                   r'D:\BrowserOS - KaihongOS\evidence\p45\center.json'],
                   capture_output=True, timeout=60)
    return open(r'D:\BrowserOS - KaihongOS\evidence\p45\center.json', encoding='utf-8', errors='replace').read()


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


sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(7)
lay = dump()

# Find the + button (accessibilityText contains 新建标签页)
plus = None
for a in walk(json.loads(lay)):
    if '新建标签页' in str(a.get('accessibilityText', '')):
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m:
            plus = list(map(int, m.groups()))
            break

if plus:
    x1, y1, x2, y2 = plus
    cx = (x1 + x2) // 2
    # The tab strip column starts at some x offset (ContainerModal window)
    # Find the window bounds
    win = None
    for a in walk(json.loads(lay)):
        if a.get('type') == 'ContainerModal':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                win = list(map(int, m.groups()))
                break

    if win:
        win_x1, win_y1, win_x2, win_y2 = win
        # Tab strip is roughly the left 200px of the window
        strip_center = win_x1 + 100  # approximately
        print('window: %s' % win)
        print('plus button: %s, center_x=%d' % (plus, cx))
        print('strip center ≈ %d' % strip_center)
        offset = cx - strip_center
        print('offset from strip center: %dpx → %s' % (offset,
              'CENTERED ✓' if abs(offset) < 30 else 'NOT CENTERED ✗'))
    else:
        print('plus: %s (window bounds not found)' % plus)
else:
    print('plus button not found in dump')

# Also take a screenshot for visual verification
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg',
               r'D:\BrowserOS - KaihongOS\evidence\p45\center_check.jpeg'],
               capture_output=True, timeout=60)
print('screenshot saved')
