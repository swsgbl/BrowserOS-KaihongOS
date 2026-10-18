"""P36 acceptance: one chat send proves hydrated key works (config.json key is empty)."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p36"


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


sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
lay = dump('probe0.json')
# 侧栏开关=右数第二工具栏钮
cands = []
for a in walk(json.loads(lay)):
    if a.get('type') == 'Button':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            if 60 <= y1 <= 400 and x1 > 900 and 'Enhance' not in str(a.get('id', '')):
                cands.append((x2, b))
cands.sort()
tg = cands[-2][1]
xs = [int(v) for v in re.findall(r'\d+', tg)]
sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))
time.sleep(2)
lay = dump('probe1.json')
ih = None
for a in walk(json.loads(lay)):
    if a.get('type') in ('TextInput', 'TextArea') and '任务' in str(a.get('hint', '')):
        b = str(a.get('bounds', ''))
        if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', b):
            ih = b
            break
print('input:', ih)
if ih:
    xs = [int(v) for v in re.findall(r'\d+', ih)]
    cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
    sh('uitest uiInput inputText %d %d "hi"' % (cx, cy))
    time.sleep(1)
    lay = dump('probe2.json')
    sb = None
    for a in walk(json.loads(lay)):
        if (a.get('text') or '') == '发送':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m and int(m.group(1)) > 900:
                sb = b
                break
    if sb:
        xs = [int(v) for v in re.findall(r'\d+', sb)]
        sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))
        print('sent; polling hilog for answer...')
        for i in range(12):
            time.sleep(6)
            out = sh('hilog -x | grep -E "P33|P36" | tail -6')
            if 'answer' in out:
                print('HILOG:', out.replace('\n', ' | ')[:400])
                break
        else:
            print('P33/P36 tail:', sh('hilog -x | grep -E "P33|P36" | tail -6').replace('\n', ' | ')[:400])
