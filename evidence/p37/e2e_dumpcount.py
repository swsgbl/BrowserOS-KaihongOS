"""P37: dump-based tab count + click +/x + menu icon pixel probe at fresh bounds."""
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


def tab_count(lay):
    # 标签行 = 竖排条里带 favicon Image 的 32px 行；用标题 Text 近似（新标签页/about:blank/标题）
    n = 0
    for a in walk(json.loads(lay)):
        if a.get('type') == 'Button':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if not m:
                continue
            x1, y1, x2, y2 = map(int, m.groups())
            # 关闭钮：条内、右上位置、28vp 宽（区别于底部 697 行的 +/search）
            if x2 <= 450 and y1 < 600 and 440 <= x2 <= 450 and (y2 - y1) <= 30:
                n += 1
    return n


def click(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))


lay = dump('c0.json')
# 用原子法定位：条内全部按钮，底部两个=+/search，顶部按 y 排第一个=首标签关闭钮
btns = []
for a in walk(json.loads(lay)):
    if a.get('type') == 'Button':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and int(m.group(3)) <= 450 and 'Enhance' not in str(a.get('id', '')):
            btns.append((int(m.group(2)), int(m.group(1)), b))
btns.sort()
closes = [b for b in btns if b[0] < 600]
footer = [b for b in btns if b[0] >= 600]
print('closes:', [(c[0], c[2]) for c in closes], ' footer:', [(f[0], f[2]) for f in footer])
n0 = len(closes)
plus = footer[0][2] if footer else None
print('tab count (close buttons):', n0)
if plus and closes:
    click(plus)
    time.sleep(2)
    lay = dump('c1.json')
    btns2 = []
    for a in walk(json.loads(lay)):
        if a.get('type') == 'Button':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m and int(m.group(3)) <= 450 and 'Enhance' not in str(a.get('id', '')):
                btns2.append((int(m.group(2)), int(m.group(1)), b))
    closes2 = [b for b in btns2 if b[0] < 600]
    n1 = len(closes2)
    print('after + :', n1, '=>', 'PASS' if n1 == n0 + 1 else 'FAIL')
    # 关掉一个（新加的那个在顶部？关闭第一个关闭钮）
    if closes2:
        click(closes2[0][2])
        time.sleep(2)
        lay = dump('c2.json')
        btns3 = []
        for a in walk(json.loads(lay)):
            if a.get('type') == 'Button':
                b = str(a.get('bounds', ''))
                m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
                if m and int(m.group(3)) <= 450 and 'Enhance' not in str(a.get('id', '')):
                    btns3.append((int(m.group(2)), int(m.group(1)), b))
        closes3 = [b for b in btns3 if b[0] < 600]
        n2 = len(closes3)
        print('after x :', n2, '=>', 'PASS' if n2 == n1 - 1 else 'FAIL')
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\c_final.jpeg'],
               capture_output=True, timeout=60)
print('DONE')
