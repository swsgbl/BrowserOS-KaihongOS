"""P33 E2E 驱动:验证 A(选中文本chip)/B(ChatMode 切换+持久化)/C(附加tab chip)/D(知道了落盘)"""
import json
import re
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')

HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p33"


def hdc(*args, tmo=40):
    r = subprocess.run([HDC, "-t", T] + list(args), capture_output=True, text=True, timeout=tmo)
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    return r.returncode, out


def sh(cmd, tmo=40):
    return hdc("shell", cmd, tmo=tmo)


def dump(name):
    sh("uitest dumpLayout -p /data/local/tmp/p33.json", tmo=60)
    hdc("file", "recv", "/data/local/tmp/p33.json", EV + "\\" + name, tmo=30)
    try:
        return open(EV + "\\" + name, encoding='utf-8', errors='replace').read()
    except OSError:
        return ''


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


def find_all(lay, needle):
    try:
        data = json.loads(lay)
    except json.JSONDecodeError:
        return []
    hits = []
    for attrs in walk(data):
        t = attrs.get('text') or ''
        if needle in t:
            b = attrs.get('bounds')
            if b and re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', str(b)):
                hits.append((t, str(b)))
    return hits


def find_one(lay, needle):
    hits = find_all(lay, needle)
    return hits[0] if hits else (None, None)


def center(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    return (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2


def click(cx, cy):
    code, out = sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
    print('   click(%d,%d) -> %s' % (cx, cy, out or 'rc=%d' % code))
    time.sleep(1.8)


def hilog_grep(tag):
    _, out = sh("hilog -x", tmo=40)
    return [l for l in out.splitlines() if tag in l]


def step(msg):
    print('\n== ' + msg, flush=True)


# ---------- D: 知道了落盘 ----------
step('D: 点击「知道了」')
lay = dump('e2e_d_before.json')
t, b = find_one(lay, '知道了')
if b:
    click(*center(b))
    time.sleep(2)
    lines = hilog_grep('[P33] overlay dismissed')
    print('   dismissed log:', lines[-1] if lines else 'NONE')
    lines2 = hilog_grep('overlay marked')
    print('   marked log:', lines2[-1] if lines2 else 'NONE')
else:
    print('   弹窗未在(可能已关闭),跳过')
