"""P37 repro: dump left tab strip — is + present? × buttons? how many tabs?"""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p37"
import os
os.makedirs(EV, exist_ok=True)


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
sh('uitest dumpLayout -p /data/local/tmp/z.json')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\repro.json'],
               capture_output=True, timeout=60)
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\repro.jpeg'],
               capture_output=True, timeout=60)
lay = open(EV + r'\repro.json', encoding='utf-8', errors='replace').read()
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


# 左侧标签列（x < 431 区域 = TabStrip 列）
print('--- left column nodes (x<431, text or small buttons) ---')
tab_titles = []
for a in walk(data):
    b = str(a.get('bounds', ''))
    m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
    if not m:
        continue
    x1, y1, x2, y2 = map(int, m.groups())
    if x2 > 431:
        continue
    t = a.get('text') or ''
    if a.get('type') == 'Text' and t:
        tab_titles.append((t[:22], b))
    if a.get('type') == 'Button':
        print('BTN', b, 'a11y=', a.get('accessibilityText'), 'id=', a.get('id'))
print('--- Text nodes in left column ---')
for t, b in tab_titles:
    print('TEXT', b, repr(t))
# 全局找 新标签页 a11y / ic_add 相关
print('--- global probe ---')
print('新建标签页 text present:', '新建标签页' in lay)
print('close a11y present:', '关闭标签' in lay)
