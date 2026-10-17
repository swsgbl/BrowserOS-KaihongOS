"""P32 E2E on Quickemu VM: bookmarks HTML import full chain (JSON-tree driven)."""
import json
import re
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')

HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p32"


def hdc(*args, tmo=40):
    r = subprocess.run([HDC, "-t", T] + list(args), capture_output=True, text=True, timeout=tmo)
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    return r.returncode, out


def sh(cmd, tmo=40):
    return hdc("shell", cmd, tmo=tmo)


def dump(name):
    sh("uitest dumpLayout -p /data/local/tmp/p32.json", tmo=60)
    hdc("file", "recv", "/data/local/tmp/p32.json", EV + "\\" + name, tmo=30)
    try:
        return open(EV + "\\" + name, encoding='utf-8', errors='replace').read()
    except OSError:
        return ''


def shot(name):
    sh("snapshot_display -f /data/local/tmp/p32shot.jpeg", tmo=40)
    hdc("file", "recv", "/data/local/tmp/p32shot.jpeg", EV + "\\" + name, tmo=30)


def walk(node):
    if isinstance(node, dict):
        attrs = node.get('attributes')
        if isinstance(attrs, dict):
            yield attrs
        for ch in (node.get('children') or []):
            yield from walk(ch)
    elif isinstance(node, list):
        for ch in node:
            yield from walk(ch)


def find(lay, needle, exact=False):
    """Return (text, bounds) of first node whose own text/hint matches."""
    try:
        data = json.loads(lay)
    except json.JSONDecodeError:
        return None, None
    for attrs in walk(data):
        for key in ('text', 'hint'):
            t = attrs.get(key) or ''
            if (exact and t == needle) or (not exact and needle in t):
                b = attrs.get('bounds')
                if b and re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', str(b)):
                    return t, str(b)
    return None, None


def center(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    return (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2


def click(cx, cy):
    sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
    time.sleep(1.8)


def step(msg):
    print('== ' + msg, flush=True)


def toolbar_menu_button(lay):
    """Rightmost Button in the toolbar row (ContainerModal windowed mode aware)."""
    try:
        data = json.loads(lay)
    except json.JSONDecodeError:
        return None
    best = None
    for attrs in walk(data):
        if attrs.get('type') != 'Button':
            continue
        b = str(attrs.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if y1 < 60 or y1 > 400:
            continue
        if x1 < 1000:
            continue
        if 'Enhance' in str(attrs.get('id', '')):
            continue  # window min/max/close
        if best is None or x2 > best[0]:
            best = (x2, b)
    return best[1] if best else None


# 1. cold start -> dashboard -> ⋮ menu -> 书签
step('cold start')
sh("aa force-stop com.browseros.kaihong")
time.sleep(1)
sh("aa start -a EntryAbility -b com.browseros.kaihong")
time.sleep(5)
lay = dump('vm_dash.json')
shot('vm_dash.jpeg')
mb = toolbar_menu_button(lay)
print('⋮ menu button:', mb)
if not mb:
    sys.exit('FAIL: toolbar menu button not found')
click(*center(mb))
lay = dump('vm_menu.json')
shot('vm_menu.jpeg')
t, b = find(lay, '书签', exact=True)
print('menu 书签 item:', t, b)
if not b:
    sys.exit('FAIL: no 书签 item in menu')
click(*center(b))

# 2. bookmarks page (verify) -> 导入 (exact match, avoid 导入登录态)
lay = dump('vm_bm.json')
if not find(lay, '搜索书签'):
    shot('vm_bm_unexpected.jpeg')
    sys.exit('FAIL: not on bookmarks page (no 搜索书签)')
shot('vm_bm.jpeg')
t, b = find(lay, '导入', exact=True)
print('导入 button:', t, b)
if not b:
    sys.exit('FAIL: no 导入 button on bookmarks page')
click(*center(b))

# 3. system picker opens -> find the html file (may need 浏览 tab)
time.sleep(2.5)
lay = dump('vm_picker.json')
shot('vm_picker.jpeg')
t, b = find(lay, 'bookmarks_sample')
print('file row:', t, b)
if not b:
    t2, b2 = find(lay, '浏览', exact=True)
    print('浏览 tab:', t2, b2)
    if b2:
        click(*center(b2))
        time.sleep(2)
        lay = dump('vm_picker2.json')
        shot('vm_picker2.jpeg')
        t, b = find(lay, 'bookmarks_sample')
        print('file row(2):', t, b)
    if not b:
        for probe in ('Docs', '文档', 'Documents'):
            t3, b3 = find(lay, probe)
            if b3:
                print('enter dir:', t3, b3)
                click(*center(b3))
                time.sleep(2)
                lay = dump('vm_picker3.json')
                shot('vm_picker3.jpeg')
                t, b = find(lay, 'bookmarks_sample')
                print('file row(3):', t, b)
                break
if not b:
    sys.exit('FAIL: bookmarks_sample.html not visible in picker')
click(*center(b))
time.sleep(1.5)

# 4. confirm (exact: 完成/确定/选择)
lay = dump('vm_picker_sel.json')
shot('vm_picker_sel.jpeg')
confirmed = False
for label in ('完成', '确定', '选择', '打开'):
    t, b = find(lay, label, exact=True)
    if b:
        print('confirm via', label, b)
        click(*center(b))
        confirmed = True
        break
if not confirmed:
    print('no explicit confirm button found (single-select may auto-return)')

# 5. back on bookmarks page -> verify count 9 + entries
time.sleep(3)
lay = dump('vm_after.json')
shot('vm_after.jpeg')
m = re.search(r'"text":"(\d+) 条"', lay)
count = m.group(1) if m else None
print('BOOKMARK COUNT =', count)
ok9 = count == '9'
for probe in ('neverssl', 'gitee', 'quotes.example.org', 'openharmony.cn/main'):
    hit = find(lay, probe)
    print('  contains %s: %s' % (probe, bool(hit[1])))

# 6. ground truth: sandbox json + hilog
rc, out = sh("cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/tabs/bookmarks.json", tmo=20)
open(EV + r"\vm_bookmarks_after.json", 'w', encoding='utf-8', errors='replace').write(out)
rc, out = hdc("shell", "hilog -x", tmo=60)
open(EV + r"\vm_hilog.txt", 'w', encoding='utf-8', errors='replace').write(out)
for line in out.splitlines():
    if 'BookmarkManager' in line:
        print('HILOG:', line.strip()[:220])

print('E2E DONE count9=%s' % ok9)
