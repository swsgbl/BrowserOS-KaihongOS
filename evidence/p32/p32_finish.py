"""P32 E2E finisher: picker has file selected -> click 打开(O) -> verify import."""
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
    return ((r.stdout or "") + (r.stderr or "")).strip()


def sh(cmd, tmo=40):
    return hdc("shell", cmd, tmo=tmo)


def dump_load(name):
    sh("uitest dumpLayout -p /data/local/tmp/p32.json", tmo=60)
    hdc("file", "recv", "/data/local/tmp/p32.json", EV + "\\" + name, tmo=30)
    return json.load(open(EV + "\\" + name, encoding='utf-8', errors='replace'))


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


def find(data, needle, exact=False):
    for attrs in walk(data):
        for key in ('text', 'hint'):
            t = attrs.get(key) or ''
            if (exact and t == needle) or (not exact and needle in t):
                b = str(attrs.get('bounds', ''))
                if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', b):
                    return t, b
    return None, None


def center(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    return (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2


data = dump_load('vm_open_btn.json')
t, b = find(data, '打开')
print('打开(O) button:', t, b)
if not b:
    sys.exit('FAIL: 打开(O) not found')
cx, cy = center(b)
print('click', cx, cy)
sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
time.sleep(4)

shot('vm_after.jpeg')
lay = json.dumps(dump_load('vm_after.json'), ensure_ascii=False)
m = re.search(r'"text":\s*"(\d+) 条"', lay)
print('BOOKMARK COUNT =', m.group(1) if m else None)
for probe in ('neverssl', 'gitee', 'quotes.example.org', 'openharmony.cn/main', 'developer.huawei.com'):
    print('  contains %s: %s' % (probe, ('"%s"' % probe) in lay or probe in lay))

out = sh("cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/tabs/bookmarks.json", tmo=20)
open(EV + r"\vm_bookmarks_after.json", 'w', encoding='utf-8', errors='replace').write(out)
print('sandbox json head:', out[:400].replace('\n', ' '))

out = hdc("shell", "hilog -x", tmo=60)
open(EV + r"\vm_hilog.txt", 'w', encoding='utf-8', errors='replace').write(out)
hits = [ln for ln in out.splitlines() if 'BookmarkManager' in ln]
print('HILOG BookmarkManager lines: %d' % len(hits))
for ln in hits[-6:]:
    print('HILOG:', ln.strip()[:220])
