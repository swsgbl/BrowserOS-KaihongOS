import subprocess, sys, time, re
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p35"


def sh(c):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=60)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump(name):
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + '\\' + name],
                   capture_output=True, timeout=60)
    return open(EV + '\\' + name, encoding='utf-8', errors='replace').read()


def input_value(lay):
    for m in re.finditer(r'"type":"TextInput"', lay):
        seg = lay[max(0, m.start() - 600):m.start()]
        t = seg.rfind('"text":"')
        if t >= 0:
            return seg[t + 8:seg.find('"', t + 8)]
    return None


def find(lay, needle):
    try:
        data = json.loads(lay)
    except Exception:
        return None
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
    for a in walk(data):
        t = a.get('text') or ''
        if needle in t:
            b = str(a.get('bounds', ''))
            if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', b):
                return b
    return None


import json
# 清空
sh('uitest uiInput click 873 501')
time.sleep(0.5)
for i in range(25):
    sh('uitest uiInput keyEvent 2055')
time.sleep(0.5)
sh('uitest uiInput inputText 873 501 a')
time.sleep(0.6)
sh('uitest uiInput inputText 873 501 @')
time.sleep(0.6)
sh('uitest uiInput inputText 873 501 b.co')
time.sleep(1)
lay = dump('a3_s5.json')
v = input_value(lay)
print('INPUT=', repr(v))
if v and re.match(r'^a@b\.co$', v):
    jb = find(lay, 'Join waitlist')
    print('join btn:', jb)
    if jb:
        xs = [int(x) for x in re.findall(r'\d+', jb)]
        sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))
        time.sleep(2.5)
        lay2 = dump('a3_s6.json')
        sh('snapshot_display -f /data/local/tmp/z.jpeg')
        subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\a3_joined.jpeg'],
                       capture_output=True, timeout=60)
        print('joined state:', ('on the list' in lay2) or ('已加入' in lay2) or ('You' in lay2))
        texts = re.findall(r'"text":"([^"]{1,40})"', lay2)
        print('texts:', [t for t in texts if t][:12])
else:
    print('email not clean — input still mangled')
