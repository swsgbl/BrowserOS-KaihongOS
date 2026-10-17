"""P33 A/B/C 验证:开侧栏→ChatMode pill→选中网页文本→chip 出现→切回 agent"""
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
    return r.returncode, ((r.stdout or "") + (r.stderr or "")).strip()


def sh(cmd, tmo=40):
    return hdc("shell", cmd, tmo=tmo)


def get_texts(name):
    sh("uitest dumpLayout -p /data/local/tmp/p33.json", tmo=60)
    hdc("file", "recv", "/data/local/tmp/p33.json", EV + "\\" + name, tmo=30)
    try:
        j = json.loads(open(EV + "\\" + name, encoding='utf-8', errors='replace').read())
    except Exception:
        return []
    out = []
    def walk(n):
        a = n.get('attributes') or {}
        if a.get('text'):
            out.append((a['text'], a.get('bounds')))
        for ch in (n.get('children') or []):
            walk(ch)
    if isinstance(j, dict):
        walk(j)
    return out


def click_b(btn):
    xs = [int(v) for v in re.findall(r'\d+', btn)]
    cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
    sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
    time.sleep(1.8)


def find_text(texts, needle):
    for t, b in texts:
        if needle in t and b and re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', str(b)):
            return t, b
    return None, None


def step(m):
    print('\n== ' + m, flush=True)


step('0) 当前页面状态')
texts = get_texts('abc_0_state.json')
print('   前12:', [t for t, _ in texts[:12]])
