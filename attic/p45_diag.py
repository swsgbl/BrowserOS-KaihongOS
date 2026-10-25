"""P45 hands-on diagnosis: actually interact with each reported broken feature."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p45"
import os
os.makedirs(EV, exist_ok=True)


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump(name='diag'):
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + '\\' + name + '.json'],
                   capture_output=True, timeout=60)
    return open(EV + '\\' + name + '.json', encoding='utf-8', errors='replace').read()


def shot(name):
    sh('snapshot_display -f /data/local/tmp/z.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + '\\' + name + '.jpeg'],
                   capture_output=True, timeout=60)


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


def click(cx, cy):
    r = sh('uitest uiInput click %d %d' % (cx, cy))
    time.sleep(1.5)


def click_b(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    click((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2)


def tab_count_from_hilog():
    out = sh('hilog -x')
    ms = re.findall(r'managerTabs=(\d+)', out)
    return int(ms[-1]) if ms else None


print('===== 1. 冷启动 =====')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(7)
lay = dump('cold')
shot('cold')
texts = [t for t in re.findall(r'"text":"([^"]{1,26})"', lay) if t]
print('TEXTS:', texts[:18])

# 检查是否在 Onboarding
if '欢迎使用' in lay or '欢迎' in str(texts):
    print('>>> ON ONBOARDING — config reset!')
    # 点跳过
    skip = None
    for a in walk(json.loads(lay)):
        if (a.get('text') or '') == '跳过':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                skip = b
                break
    if skip:
        click_b(skip)
        time.sleep(2)
        lay = dump('after_skip')
        shot('after_skip')
        print('>>> after skip, hero present:', 'What should your agent' in lay)

print('===== 2. 标签页 × 关闭按钮实测 =====')
# 先加两个标签
lay = dump('pre_tabs')
# 找底部 + 按钮（当前在底部）
plus = None
close_btn = None
btns = []
for a in walk(json.loads(lay)):
    if a.get('type') == 'Button':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            if x2 <= 500 and y1 > 100 and 'Enhance' not in str(a.get('id', '')):
                btns.append((y1, x1, b, a.get('accessibilityText', '')))
btns.sort()
print('left col buttons:', [(b[2], b[3]) for b in btns])
if len(btns) >= 2:
    close_btn = btns[0][2]  # topmost = first tab's close
    plus_btn = btns[-2][2] if len(btns) >= 2 else None  # second from bottom
print('close_btn:', close_btn, ' plus_btn:', plus_btn)

if plus_btn:
    n0 = tab_count_from_hilog()
    click_b(plus_btn)
    time.sleep(2)
    n1 = tab_count_from_hilog()
    print('>>> + click: tabs %s -> %s' % (n0, n1), '=>', 'WORKS' if n1 and n0 and n1 == n0 + 1 else 'BROKEN')

if close_btn:
    n_before = tab_count_from_hilog()
    click_b(close_btn)
    time.sleep(2)
    n_after = tab_count_from_hilog()
    print('>>> × click: tabs %s -> %s' % (n_before, n_after), '=>', 'WORKS' if n_before and n_after and n_after == n_before - 1 else 'BROKEN')
    # 再试一次
    lay2 = dump('after_close')
    close2 = None
    for a in walk(json.loads(lay2)):
        if a.get('type') == 'Button':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                x1, y1, x2, y2 = map(int, m.groups())
                if x2 <= 500 and y1 > 100 and y1 < 300 and 'Enhance' not in str(a.get('id', '')):
                    close2 = b
                    break
    if close2:
        n2 = tab_count_from_hilog()
        click_b(close2)
        time.sleep(2)
        n3 = tab_count_from_hilog()
        print('>>> × retry: tabs %s -> %s' % (n2, n3), '=>', 'WORKS' if n2 and n3 and n3 == n2 - 1 else 'BROKEN')

print('===== 3. 搜索引擎 =====')
lay = dump('search_check')
print('config searchEngine:', sh("grep -o 'searchEngineId[^,]*' /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json"))
print('9 engines in code:', 'google' in open('entry/src/main/ets/common/SearchEngines.ets', encoding='utf-8').read().lower())

print('===== 4. 地址栏导航 =====')
# 找地址栏 TextInput
omni = None
for a in walk(json.loads(lay)):
    if a.get('type') == 'TextInput' and 'URL' in str(a.get('hint', '')):
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m:
            omni = b
            break
print('omnibox:', omni)
if omni:
    xs = [int(v) for v in re.findall(r'\d+', omni)]
    cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
    sh('uitest uiInput inputText %d %d "example.com"' % (cx, cy))
    time.sleep(1)
    sh('uitest uiInput keyEvent 2054')  # ENTER
    time.sleep(5)
    lay3 = dump('after_nav')
    shot('after_nav')
    has_web = 'Example' in lay3 or 'example' in lay3.lower()
    print('>>> navigate example.com:', 'LOADED' if has_web else 'NOT LOADED')
    print('>>> hilog nav:', sh('hilog -x | grep -c navigate') or '0')

print('DONE')
