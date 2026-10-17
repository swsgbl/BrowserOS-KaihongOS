"""P33 主动日志验证 v2:先切网页 tab 再双击选词"""
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
    return ((r.stdout or "") + (r.stderr or "")).strip()


def sh(cmd, tmo=30):
    return hdc("shell", cmd, tmo=tmo)


def dump(name):
    sh("uitest dumpLayout -p /data/local/tmp/p33.json", tmo=60)
    hdc("file", "recv", "/data/local/tmp/p33.json", EV + "\\" + name, tmo=30)
    try:
        return json.loads(open(EV + "\\" + name, encoding='utf-8', errors='replace').read())
    except Exception:
        return {}


def texts_of(j):
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


def click(cx, cy, wait=1.6):
    sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
    time.sleep(wait)


sh("hilog -r")
print('== 前台拉起')
sh("aa start -a EntryAbility -b com.browseros.kaihong")
time.sleep(3.5)

j = dump('v4_state.json')
ts = texts_of(j)
print('前10:', [t for t, _ in ts[:10]])
# 左侧竖排标签区 [265,180][431,750]:找 Example Domain 标签
b = None
for t, bb in ts:
    if 'Example Domain' in t and bb:
        ys = [int(v) for v in re.findall(r'\d+', bb)]
        if ys[0] < 431 and ys[1] > 180:  # 左栏
            b = bb
            break
if not b:
    # 任何左栏 tab(排除 dashboard 文本)
    for t, bb in ts:
        if bb:
            ys = [int(v) for v in re.findall(r'\d+', bb)]
            if ys[0] < 431 and 180 < ys[1] < 750 and '驾驶舱' not in t and len(t) > 2:
                b = bb
                print('fallback tab:', t, bb)
                break
if b:
    print('== 切到网页 tab', b)
    click(*[int(v) for v in re.findall(r'\d+', b)][0:1], 1)  # placeholder
    xs = [int(v) for v in re.findall(r'\d+', b)]
    click((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2, 4)
else:
    print('未找到网页 tab!')
    sys.exit(1)

print('== 网页加载后双击选词')
click(700, 480, 0.6)
sh("uitest uiInput click 700 480", tmo=25)
time.sleep(0.25)
sh("uitest uiInput click 700 480", tmo=25)
time.sleep(4)

out = sh("hilog -x", tmo=60)
open(EV + r"\v4_hilog.txt", "w", encoding="utf-8").write(out)
for needle, name in [
    ('selection captured', 'A 选区捕获'),
    ('auto-attached', 'C tab 附加'),
]:
    hits = [l.split('JSAPP: ')[-1] for l in out.splitlines() if needle in l and 'JSAPP: ' in l]
    print('%-10s: %s' % (name, hits[-1] if hits else '未见'))
