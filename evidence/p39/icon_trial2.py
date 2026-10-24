import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\attic"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(7)
sh('uitest dumpLayout -p /data/local/tmp/z.json')
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\t2.json'], capture_output=True, timeout=60)
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\t2.jpeg'], capture_output=True, timeout=60)
lay = open(EV + r'\t2.json', encoding='utf-8', errors='replace').read()
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


imgs = []
for a in walk(data):
    if a.get('type') == 'Image':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and 8 <= (int(m.group(4)) - int(m.group(2))) <= 30:
            imgs.append((int(m.group(2)), b))  # (y, bounds)
imgs.sort()
print('bottom images:', [b for _, b in imgs if _ > 500][:6])
from PIL import Image
im = Image.open(EV + r'\t2.jpeg').convert('L')
# 探窗口内容区（y>150 非系统栏）的图标：favicon 区与底部两枚
probes = [b for _, b in imgs if 150 < _ < 500][:3] + [b for _, b in imgs if _ > 600][:3]
for b in probes:
    xs = [int(v) for v in re.findall(r'\d+', b)]
    box = (xs[0] + 2, xs[1] + 2, xs[2] - 2, xs[3] - 2)
    if box[2] <= box[0] or box[3] <= box[1]:
        continue
    px = list(im.crop(box).getdata())
    bg = max(set(px), key=px.count)
    nonbg = sum(1 for v in px if abs(v - bg) > 25)
    print('%s non-bg %.1f%%' % (b, 100.0 * nonbg / len(px)))
