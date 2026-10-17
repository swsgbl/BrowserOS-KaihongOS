"""P33 终版验证:书签开网页→侧栏已开→双击选词→A/C 日志+chip;B 点 pill 切换"""
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


def dump_texts(name):
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


def click(cx, cy, wait=1.6):
    sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
    time.sleep(wait)


sh("hilog -r")
print('== 0) 当前态(侧栏应已开)')
ts = dump_texts('v6_0.json')
print('   pill:', [t for t, _ in ts if 'Mode ON' in t])

# 1) 书签栏点 Example Domain(书签栏 y 220-247, x>443)
b = None
for t, bb in ts:
    if 'Example Domain' in t and bb:
        ys = [int(v) for v in re.findall(r'\d+', bb)]
        if 220 < ys[1] < 250 and ys[0] > 431:
            b = bb
            break
if not b:
    print('书签栏无 Example Domain! texts:', [t for t, _ in ts if 'Example' in t])
    sys.exit(1)
xs = [int(v) for v in re.findall(r'\d+', b)]
print('== 1) 点书签开 Example Domain', b)
click((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2, 5)

# 2) 网页加载完,双击选词
print('== 2) 双击选词')
click(700, 450, 0.6)
sh("uitest uiInput click 700 450", tmo=25)
time.sleep(0.3)
sh("uitest uiInput click 700 450", tmo=25)
time.sleep(4.5)

out = sh("hilog -x", tmo=60)
open(EV + r"\v6_hilog.txt", "w", encoding="utf-8").write(out)
for needle, name in [
    ('selection captured', 'A 选区捕获'),
    ('auto-attached', 'C tab 附加'),
]:
    hits = [l.split('JSAPP: ')[-1] for l in out.splitlines() if needle in l and 'JSAPP: ' in l]
    print('%-10s: %s' % (name, hits[-1] if hits else '未见'))
ts = dump_texts('v6_sel.json')
print('   已选 chip:', [t for t, _ in ts if '已选' in t] or '未见')
print('   附加 chip:', [t for t, _ in ts if 'Example' in t][:2] or '未见')

# 3) B: 点 Agent Mode pill 切 chat
b = None
for t, bb in ts:
    if 'Agent Mode ON' in t:
        b = bb
        break
if b:
    xs = [int(v) for v in re.findall(r'\d+', b)]
    print('== 3) B: 切 chat 模式', b)
    click((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2, 2.2)
    ts = dump_texts('v6_chat.json')
    print('   Chat pill:', [t for t, _ in ts if 'Chat Mode ON' in t] or '未出现!')
    out = sh("hilog -x", tmo=60)
    hits = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'chat mode' in l and 'JSAPP: ' in l]
    print('   模式日志:', hits[-2:] if hits else '未见')
