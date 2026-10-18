"""P37 verify: pixel-probe icons + click + (new tab) and x (close tab) E2E."""
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


sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
sh('uitest dumpLayout -p /data/local/tmp/z.json')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\fix.json'],
               capture_output=True, timeout=60)
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\fix.jpeg'],
               capture_output=True, timeout=60)

lay = open(EV + r'\fix.json', encoding='utf-8', errors='replace').read()
data = json.loads(lay)

# 找标签列底部按钮（+ 与 tab-search）与首标签关闭钮
plus_btn = None
close_btn = None
cands = []
for a in walk(data):
    if a.get('type') == 'Button':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if x2 <= 440 and y1 > 100 and 'Enhance' not in str(a.get('id', '')):
            cands.append((y1, x1, b))
cands.sort()
print('left-column buttons (y,x,bounds):', cands)
if len(cands) >= 3:
    # 底部两个=+与search；顶部第一个=首标签的关闭钮
    close_btn = cands[0][2]
    plus_btn = cands[-2][2] if len(cands) >= 2 else None
print('close_btn:', close_btn, ' plus_btn:', plus_btn)


def count_tabs():
    out = sh('hilog -x | grep managerTabs | tail -2')
    m = re.findall(r'managerTabs=(\d+)', out)
    return int(m[-1]) if m else None


def click_b(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))


if plus_btn:
    n0 = count_tabs()
    print('tabs before +:', n0)
    click_b(plus_btn)
    time.sleep(2)
    n1 = count_tabs()
    print('tabs after + :', n1, '->', 'PASS' if (n0 is not None and n1 == n0 + 1) else 'CHECK')
if close_btn:
    click_b(close_btn)
    time.sleep(2)
    n2 = count_tabs()
    print('tabs after x :', n2, '->', 'PASS' if (n1 is not None and n2 == n1 - 1) else 'CHECK')
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\fix_after.jpeg'],
               capture_output=True, timeout=60)
