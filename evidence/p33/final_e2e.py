"""Final: banner interaction + sidepanel chat-mode E2E."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p33"


def sh(cmd, timeout=90):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def click(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    print('    click', (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2)
    print('    ', sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))[:40])


def dump(name):
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + '\\' + name],
                   capture_output=True, timeout=60)
    return open(EV + '\\' + name, encoding='utf-8', errors='replace').read()


def shot(name):
    sh('snapshot_display -f /data/local/tmp/z.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + '\\' + name],
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


def find(lay, needle, exact=False):
    try:
        data = json.loads(lay)
    except json.JSONDecodeError:
        return None
    for a in walk(data):
        t = a.get('text') or ''
        if (exact and t == needle) or (not exact and needle in t):
            b = str(a.get('bounds', ''))
            if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', b):
                return b
    return None


print('== banner CTA interaction')
lay = dump('b0.json')
cta = find(lay, 'Request early access')
print('  CTA:', cta)
if cta:
    click(cta)
    time.sleep(1.5)
    lay = dump('b1.json')
    print('  toast shown:', '已加入' in lay)
    print('  banner hidden:', find(lay, 'Ultrafast') is None)
    sh('aa force-stop com.browseros.kaihong')
    time.sleep(1)
    sh('aa start -a EntryAbility -b com.browseros.kaihong')
    time.sleep(5)
    lay = dump('b2.json')
    print('  after restart banner hidden (persisted):', find(lay, 'Ultrafast') is None)
    shot('b_banner_done.jpeg')

print('== sidepanel chat mode E2E')
# 侧栏开关: 工具栏按钮 x=1269 (ic_agent, hmh btn7 笔记)
lay = dump('sp0.json')
btn = None
try:
    data = json.loads(lay)
    best = -1
    for a in walk(data):
        if a.get('type') != 'Button':
            continue
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', str(a.get('bounds', '')))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if 60 <= y1 <= 400 and x1 > 1150 and 'Enhance' not in str(a.get('id', '')):
            if x1 == 1269:
                btn = ''.join('[%d,%d][%d,%d]' % (x1, y1, x2, y2))
except Exception:
    pass
if not btn:
    print('  fallback: try x=1269 fixed bounds [1269,185][1299,215]')
    btn = '[1269,185][1299,215]'
print('  sidepanel toggle btn:', btn)
click(btn)
time.sleep(2)
lay = dump('sp1.json')
pill = find(lay, 'Agent Mode ON') or find(lay, 'Chat Mode ON')
print('  mode pill:', pill)
shot('sp1.jpeg')
if pill:
    click(pill)
    time.sleep(1.5)
    lay = dump('sp2.json')
    print('  now Chat Mode ON:', find(lay, 'Chat Mode ON') is not None)
    shot('sp2.jpeg')
    # 输入框: 侧栏右停靠的 TextInput
    ih = None
    try:
        data = json.loads(lay)
        for a in walk(data):
            if a.get('type') == 'TextInput':
                b = str(a.get('bounds', ''))
                m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
                if m and int(m.group(1)) > 900:
                    ih = b
                    print('  input', b, 'hint=', a.get('hint'))
                    break
    except Exception:
        pass
    if ih:
        xs = [int(v) for v in re.findall(r'\d+', ih)]
        cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
        r = sh('uitest uiInput inputText %d %d "一句话介绍你自己"' % (cx, cy))
        print('  inputText:', r[:40])
        time.sleep(1.2)
        lay = dump('sp3.json')
        sb = find(lay, '发送')
        print('  发送 btn:', sb)
        if sb:
            click(sb)
            print('  sent; polling hilog for chat-mode single-shot...')
            hit = False
            for i in range(12):
                time.sleep(6)
                out = sh('hilog -x | grep -E "chat mode|chat-mode|single-shot" | tail -4')
                if out.strip():
                    print('  HILOG:', out.replace('\n', ' | ')[:400])
                    hit = True
                    break
            if not hit:
                out = sh('hilog -x | grep -E "P33" | tail -6')
                print('  P33 tail:', out.replace('\n', ' | ')[:400])
            time.sleep(2)
            lay = dump('sp4.json')
            shot('sp4_chat_answer.jpeg')
            print('  final dump len:', len(lay))
print('DONE')
