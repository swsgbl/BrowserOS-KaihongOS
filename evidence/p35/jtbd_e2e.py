"""P35-A jtbd E2E: 5 chat sends -> popup -> Take Survey -> 3 questions -> done -> never again."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p35"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def click_b(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))


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


def pill_text(lay):
    i = lay.find('Mode ON')
    if i < 0:
        return None, None
    j = lay.rfind('"attributes"', 0, i)
    seg = lay[j:i + 300]
    k = seg.find('"text":"')
    b = re.search(r'"bounds":"(\[\d+,\d+\]\[\d+,\d+\])"', seg)
    return (seg[k + 8:seg.find('"', k + 8)] if k >= 0 else None), (b.group(1) if b else None)


def side_input(lay):
    try:
        data = json.loads(lay)
    except Exception:
        return None
    for a in walk(data):
        if a.get('type') in ('TextInput', 'TextArea') and '任务' in str(a.get('hint', '')):
            b = str(a.get('bounds', ''))
            if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', b):
                return b
    return None


def toolbar_toggle(lay):
    """右数第二个工具栏 Button = 侧栏开关（最右是 ⋮；排除 Enhance 窗口钮；窗口化坐标漂移自适应）"""
    try:
        data = json.loads(lay)
    except json.JSONDecodeError:
        return None
    cands = []
    for a in walk(data):
        if a.get('type') != 'Button':
            continue
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if y1 < 60 or y1 > 400 or x1 < 900 or 'Enhance' in str(a.get('id', '')):
            continue
        cands.append((x2, b))
    if len(cands) < 2:
        return None
    cands.sort()
    return cands[-2][1]


print('== cold start -> sidepanel -> chat mode')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
lay0 = dump('j0_pre.json')
tg = toolbar_toggle(lay0)
print('  sidepanel toggle btn:', tg)
if not tg:
    sys.exit('no toolbar toggle found')
click_b(tg)
time.sleep(2)
lay = dump('j0.json')
t, b = pill_text(lay)
print('  pill:', t)
if t == 'Agent Mode ON' and b:
    click_b(b)
    time.sleep(1.5)
    lay = dump('j0b.json')
    t, b = pill_text(lay)
    print('  after toggle:', t)

print('== 5 chat sends')
ih = side_input(lay)
print('  input:', ih)
if not ih:
    sys.exit('no sidepanel input')
xs = [int(v) for v in re.findall(r'\d+', ih)]
cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
popup = None
for i in range(5):
    sh('uitest uiInput inputText %d %d "第%d条测试消息"' % (cx, cy, i + 1))
    time.sleep(1)
    lay = dump('j_send%d.json' % i)
    sb = find(lay, '发送')
    if not sb:
        print('  no send button at round', i)
        break
    click_b(sb)
    print('  sent round', i + 1)
    # 等回复（agent 气泡出现/弹窗出现）
    for w in range(14):
        time.sleep(5)
        lay = dump('j_wait%d_%d.json' % (i, w))
        if 'Help us improve BrowserOS' in lay:
            popup = lay
            print('  POPUP after round', i + 1)
            break
        # 粗略：回复出现=发送钮从"停止"恢复 或 直接继续
        if find(lay, '停止') is None:
            break
    if popup:
        break

if popup is None:
    lay = dump('j_final_check.json')
    popup = lay if 'Help us improve BrowserOS' in lay else None
    print('  popup in final check:', popup is not None)
if popup:
    shot('j_popup.jpeg')
    print('  Maybe Later btn:', find(popup, 'Maybe Later'))
    ts = find(popup, 'Take Survey')
    print('  Take Survey btn:', ts)
    if ts:
        click_b(ts)
        time.sleep(2.5)
        lay2 = dump('j_survey_welcome.json')
        shot('j_survey_welcome.jpeg')
        print('  Welcome title:', 'Share Your Experience' in lay2)
        ss = find(lay2, 'Start Survey')
        print('  Start Survey:', ss)
        if ss:
            click_b(ss)
            time.sleep(2)
            for q in range(3):
                layq = dump('j_q%d.json' % q)
                ihq = None
                try:
                    for a in walk(json.loads(layq)):
                        if a.get('type') in ('TextInput', 'TextArea'):
                            bb = str(a.get('bounds', ''))
                            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', bb)
                            if m:
                                ihq = bb
                                break
                except Exception:
                    pass
                print('  Q%d input:' % (q + 1), ihq)
                if not ihq:
                    break
                qx = [int(v) for v in re.findall(r'\d+', ihq)]
                sh('uitest uiInput inputText %d %d "回答%d"' % ((qx[0] + qx[2]) // 2, (qx[1] + qx[3]) // 2, q + 1))
                time.sleep(1)
                layq2 = dump('j_q%d_filled.json' % q)
                nb = find(layq2, '发送') or find(layq2, '下一题') or find(layq2, '提交')
                print('  Q%d action btn:' % (q + 1), nb)
                if nb:
                    click_b(nb)
                    time.sleep(1.5)
            lay3 = dump('j_survey_done.json')
            shot('j_survey_done.jpeg')
            print('  done/thanks:', ('感谢' in lay3) or ('Thank' in lay3) or ('完成' in lay3))
print('DONE')
