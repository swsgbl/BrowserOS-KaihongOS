"""P45 deeper diagnosis: navigation with proper input, + button position."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p45"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump(name):
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


def find_input(lay, hint_key='URL'):
    for a in walk(json.loads(lay)):
        if a.get('type') == 'TextInput' and hint_key in str(a.get('hint', '')):
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                return list(map(int, m.groups()))
    return None


print('===== 1. 地址栏：清空→输入→ENTER =====')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
lay = dump('nav_test')
omni = find_input(lay)
print('omnibox bounds:', omni)
if omni:
    cx, cy = (omni[0] + omni[2]) // 2, (omni[1] + omni[3]) // 2
    # 聚焦
    sh('uitest uiInput click %d %d' % (cx, cy))
    time.sleep(0.8)
    # 清空（当前有 about:blank = 11 字符，DEL 20 次）
    for i in range(20):
        sh('uitest uiInput keyEvent 2055')  # DEL
    time.sleep(0.5)
    # 输入
    sh('uitest uiInput inputText %d %d "https://example.com"' % (cx, cy))
    time.sleep(1)
    # 验证输入内容
    lay_check = dump('input_check')
    for a in walk(json.loads(lay_check)):
        if a.get('type') == 'TextInput' and 'URL' in str(a.get('hint', '')):
            print('input text now:', repr(a.get('text', '')))
            break
    # ENTER
    sh('uitest uiInput keyEvent 2054')  # ENTER
    time.sleep(6)
    lay_after = dump('after_enter')
    shot('after_enter')
    # 检查是否加载了页面
    texts_after = [t for t in re.findall(r'"text":"([^"]{1,30})"', lay_after) if t]
    print('after ENTER texts:', texts_after[:14])
    print('Example in page:', 'Example' in lay_after or 'example' in lay_after)
    # hilog 导航
    hilog = sh('hilog -x')
    nav_lines = [l for l in hilog.splitlines() if 'navigate' in l.lower() or 'onPageEnd' in l or 'loadUrl' in l]
    for l in nav_lines[:4]:
        print('NAV:', l.strip()[:120])
    if not nav_lines:
        print('NAV: NO NAVIGATION LOGS')

print('===== 2. + 按钮位置 vs 上游 =====')
# 当前 + 在最底部（y~704）；上游在最后一个标签正下方
# 数标签数量
tab_texts = []
for a in walk(json.loads(lay)):
    if (a.get('text') or '') in ('about:blank', '新标签页', 'Example Domain') or '新标签' in str(a.get('text', '')):
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and int(m.group(1)) < 200:
            tab_texts.append((int(m.group(2)), (a.get('text') or '')[:15]))
tab_texts.sort()
print('tabs found:', tab_texts)
print('+ currently at y=704 (bottom of column)')
if tab_texts:
    print('last tab at y=%d — + should be at ~y=%d (right below)' % (tab_texts[-1][0], tab_texts[-1][0] + 36))

print('===== 3. 新标签页 Dashboard 检查 =====')
# P31 说冷启动应落 dashboard——当前显示 about:blank 标签
print('showDashboard in dump:', 'What should your agent' in lay)
print('dashboard hint:', '问点什么' in lay)
# 检查 hilog 的冷启动日志
hilog2 = sh('hilog -x')
cold = [l for l in hilog2.splitlines() if 'cold start' in l.lower() or 'dashboard' in l.lower()]
for l in cold[:3]:
    print('COLD:', l.strip()[:120])
