"""P33-B chat-mode single-shot send E2E (fixed assertions + TextArea)."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p33"


def sh(cmd, timeout=90):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
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


def pill_text(lay):
    i = lay.find('Mode ON')
    if i < 0:
        return None, None
    j = lay.rfind('"attributes"', 0, i)
    seg = lay[j:i + 300]
    k = seg.find('"text":"')
    b = re.search(r'"bounds":"(\[\d+,\d+\]\[\d+,\d+\])"', seg)
    return (seg[k + 8:seg.find('"', k + 8)] if k >= 0 else None), (b.group(1) if b else None)


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


# 冷启动 → 开侧栏
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
sh('uitest uiInput click 1284 200')
time.sleep(2)
lay = dump('c0.json')
t, b = pill_text(lay)
print('pill now:', t, b)
if t == 'Agent Mode ON' and b:
    click_b(b)
    time.sleep(1.5)
    lay = dump('c1.json')
    t, b = pill_text(lay)
    print('after toggle:', t, b)
shot('c_chat_mode.jpeg')

# 侧栏任务输入（TextInput 或 TextArea，hint 含 任务）
ih = None
try:
    data = json.loads(lay)
    for a in walk(data):
        if a.get('type') in ('TextInput', 'TextArea') and '任务' in str(a.get('hint', '')):
            bb = str(a.get('bounds', ''))
            if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', bb):
                ih = bb
                print('input found:', a.get('type'), bb, a.get('hint'))
                break
except Exception as e:
    print('walk err', e)
if not ih:
    print('NO SIDE INPUT — dump TextInput/TextArea all:')
    try:
        for a in walk(json.loads(lay)):
            if a.get('type') in ('TextInput', 'TextArea'):
                print('  ', a.get('type'), a.get('bounds'), repr(str(a.get('hint'))[:20]))
    except Exception:
        pass
    sys.exit(1)

xs = [int(v) for v in re.findall(r'\d+', ih)]
cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
r = sh('uitest uiInput inputText %d %d "用一句话介绍你自己"' % (cx, cy))
print('inputText:', r[:40])
time.sleep(1.2)
lay = dump('c2.json')
# 发送按钮：侧栏内的 发送 文本或按钮
sb = None
try:
    for a in walk(json.loads(lay)):
        tt = a.get('text') or ''
        if tt == '发送':
            bb = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', bb)
            if m and int(m.group(1)) > 950:
                sb = bb
                break
except Exception:
    pass
print('发送 btn:', sb)
if not sb:
    i2 = lay.find('发送')
    print('发送 raw idx:', i2)
else:
    click_b(sb)
    print('sent — polling hilog for single-shot chat reply...')
    hit = False
    for k in range(15):
        time.sleep(6)
        out = sh('hilog -x | grep -E "P33" | tail -5')
        if 'chat' in out.lower() and ('reply' in out.lower() or 'mode' in out.lower()):
            print('HILOG:', out.replace('\n', ' | ')[:500])
            hit = True
            break
    if not hit:
        print('P33 tail:', sh('hilog -x | grep "P33" | tail -5').replace('\n', ' | ')[:400])
    time.sleep(3)
    lay = dump('c3.json')
    shot('c3_answer.jpeg')
    print('answer-era dump len:', len(lay))
print('DONE')
