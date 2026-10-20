"""P38 verify: atomic dump+screenshot, locate strip buttons + favicon, report bounds for pixel probe."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r'D:\BrowserOS - KaihongOS\evidence\p38'
import os
os.makedirs(EV, exist_ok=True)


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(7)
sh('uitest dumpLayout -p /data/local/tmp/z.json')
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\v.json'],
               capture_output=True, timeout=60)
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\v.jpeg'],
               capture_output=True, timeout=60)
lay = open(EV + r'\v.json', encoding='utf-8', errors='replace').read()


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


data = json.loads(lay)
btns = []
imgs = []
for a in walk(data):
    if a.get('type') == 'Button':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and int(m.group(3)) <= 450 and 'Enhance' not in str(a.get('id', '')):
            btns.append((int(m.group(2)), b))
    if a.get('type') == 'Image':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and int(m.group(3)) <= 450 and 100 < int(m.group(2)) < 700 and (int(m.group(4)) - int(m.group(2))) <= 30:
            imgs.append(b)
btns.sort()
print('strip buttons:', [b for _, b in btns])
print('strip small images:', imgs[:10])
