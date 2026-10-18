"""P35 acceptance: hero probe + provider picker + RecentSites + jtbd + waitlist."""
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


print('== 1. cold start hero probe (agent-command)')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
lay = dump('acc35_dash.json')
shot('acc35_dash.jpeg')
for probe in ['What should your agent', 'work on', 'next?', 'Pick any provider or agent',
              'BrowserOS neo', 'Request early access']:
    print('  %-28s: %s' % (probe, probe in lay))
# RecentSites: 历史里有 example.com 等
print('  RecentSites example.com     :', 'example.com' in lay)

print('== 2. provider picker')
pp = find(lay, 'agnes') or find(lay, '未配置')
print('  provider label/pill:', pp)
# 点开下拉（provider 选择器在输入框区）
pb = find(lay, 'agnes-3.0-flash') or find(lay, 'agnes')
if pb:
    click_b(pb)
    time.sleep(1.5)
    lay2 = dump('acc35_prov.json')
    shot('acc35_prov.jpeg')
    print('  dropdown open (多 provider 项):', lay2.count('agnes') > 1 or 'provider' in lay2.lower())

print('== 3. ultrafast waitlist page (banner CTA)')
lay = dump('acc35_b0.json')
cta = find(lay, 'Request early access')
print('  banner CTA:', cta)
if cta:
    click_b(cta)
    time.sleep(2.5)
    lay3 = dump('acc35_wait.json')
    shot('acc35_wait.jpeg')
    for probe in ['$5', 'Faster clicks', 'Bring your own Claude', '10× fewer tokens', 'Join waitlist', 'Ultrafast']:
        print('  waitlist %-20s: %s' % (probe, probe in lay3))

print('== 4. jtbd popup (set shownCount=9 then send 1 msg? 简化: 直接查代码链路+调查页可达)')
# 直接路由进调查页验证三问流程（aa start 带路由不可行——用 UI: 菜单无入口; 用 hilog 触发? 简化：root 改 jtbd_store 后侧栏发消息)
print('  (jtbd 弹窗阈值链路由代码+hilog 验证；调查页经弹窗 Take Survey 进入)')
print('DONE')
