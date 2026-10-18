"""P35 waitlist join retry: clear input via DEL keys, type valid email, join."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p35"


def sh(cmd, timeout=90):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def click_xy(x, y):
    sh('uitest uiInput click %d %d' % (x, y))


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


lay = dump('a3_s0.json')
ih = None
try:
    for a in walk(json.loads(lay)):
        if a.get('type') == 'TextInput':
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if m:
                ih = b
                break
except Exception:
    pass
print('email input:', ih)
if not ih:
    sys.exit('no input on waitlist page (still there?)')
xs = [int(v) for v in re.findall(r'\d+', ih)]
cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
click_xy(cx, cy)
time.sleep(0.8)
for i in range(45):
    sh('uitest uiInput keyEvent 2055')  # DEL
time.sleep(0.6)
lay = dump('a3_s1.json')
try:
    for a in walk(json.loads(lay)):
        if a.get('type') == 'TextInput':
            print('after DEL, input text=', repr(a.get('text')))
except Exception:
    pass
sh('uitest uiInput inputText %d %d "user@example.com"' % (cx, cy))
time.sleep(1)
lay = dump('a3_s2.json')
try:
    for a in walk(json.loads(lay)):
        if a.get('type') == 'TextInput':
            print('typed, input text=', repr(a.get('text')))
except Exception:
    pass
jb = find(lay, 'Join waitlist')
print('join btn:', jb)
if jb:
    jx = [int(v) for v in re.findall(r'\d+', jb)]
    click_xy((jx[0] + jx[2]) // 2, (jx[1] + jx[3]) // 2)
    time.sleep(2.5)
    lay = dump('a3_s3.json')
    shot('a3_joined.jpeg')
    joined = ('on the list' in lay) or ('已加入' in lay) or ('列表' in lay)
    print('joined state:', joined)
    texts = re.findall(r'"text":"([^"]{1,40})"', lay)
    print('page texts:', [t for t in texts if t][:12])
