"""P35 acceptance round 2: banner->waitlist chain + RecentSites + provider pill fix."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p35"


def sh(cmd, timeout=90):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def click_b(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))


def recv(remote, local):
    subprocess.run([HDC, '-t', T, 'file', 'recv', remote, EV + '\\' + local],
                   capture_output=True, timeout=60)


def dump(name):
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    recv('/data/local/tmp/z.json', name)
    return open(EV + '\\' + name, encoding='utf-8', errors='replace').read()


def shot(name):
    sh('snapshot_display -f /data/local/tmp/z.jpeg')
    recv('/data/local/tmp/z.jpeg', name)


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


print('== cold start (ultrafast prefs cleared earlier)')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(7)
lay = dump('a2_dash.json')
shot('a2_dash.jpeg')
print('  hero next?      :', 'next?' in lay)
print('  provider pill   :', find(lay, 'agnes') is not None or find(lay, '未配置') is not None)
pp = find(lay, 'agnes-3.0-flash')
print('  pill=当前模型名  :', pp)
print('  banner CTA      :', find(lay, 'Request early access'))
# RecentSites 探测：域名 Text
doms = []
try:
    for a in walk(json.loads(lay)):
        t = a.get('text') or ''
        if re.search(r'\.(com|cn|org|net)\b', t):
            doms.append(t[:24])
except Exception:
    pass
print('  recent domains  :', doms[:8])

print('== banner CTA -> waitlist page')
cta = find(lay, 'Request early access')
if cta:
    click_b(cta)
    time.sleep(2.5)
    lay2 = dump('a2_wait.json')
    shot('a2_wait.jpeg')
    for probe in ['$5', 'Faster clicks', 'Bring your own Claude', '10× fewer tokens', 'Join waitlist']:
        print('  waitlist %-20s: %s' % (probe, probe in lay2))
    # email 输入 + 非法校验
    ih = None
    try:
        for a in walk(json.loads(lay2)):
            if a.get('type') == 'TextInput':
                b = str(a.get('bounds', ''))
                m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
                if m:
                    ih = b
                    break
    except Exception:
        pass
    print('  email input:', ih)
    if ih:
        xs = [int(v) for v in re.findall(r'\d+', ih)]
        cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
        sh('uitest uiInput inputText %d %d "bad-email"' % (cx, cy))
        time.sleep(1)
        jb = find(lay2 or dump('a2_w1.json'), 'Join waitlist')
        if jb:
            click_b(jb)
            time.sleep(1.5)
            lay3 = dump('a2_w2.json')
            print('  invalid email error:', ('邮箱' in lay3) or ('email' in lay3.lower()) or ('无效' in lay3) or ('Invalid' in lay3))
        # 合法 email
        sh('uitest uiInput inputText %d %d "user@example.com"' % (cx, cy))
        time.sleep(1)
        lay4 = dump('a2_w3.json')
        jb = find(lay4, 'Join waitlist')
        if jb:
            click_b(jb)
            time.sleep(2)
            lay5 = dump('a2_w4.json')
            shot('a2_w4.jpeg')
            print('  joined state:', ('on the list' in lay5) or ('已加入' in lay5))
print('DONE')
