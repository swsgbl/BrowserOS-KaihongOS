"""P33 主动日志验证 v3:正确序列 = 切网页tab → 开侧栏(btn7) → 双击选词"""
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
print('== 前台拉起')
sh("aa start -a EntryAbility -b com.browseros.kaihong")
time.sleep(3.5)

# 1) 左栏找 Example Domain 标签(左栏 x<431,排除顶部)
ts = dump_texts('v5_state.json')
b = None
for t, bb in ts:
    if 'Example Domain' in t and bb:
        ys = [int(v) for v in re.findall(r'\d+', bb)]
        if ys[0] < 431 and ys[1] > 185:
            b = bb
            break
if b:
    xs = [int(v) for v in re.findall(r'\d+', b)]
    print('== 切 Example Domain tab', b)
    click((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2, 4.5)
else:
    print('左栏无 Example Domain 标签,tolerant 继续')

# 2) 开侧栏
print('== 开侧栏 btn7')
click(1284, 200, 2.5)
ts = dump_texts('v5_panel.json')
mode = [t for t, _ in ts if 'Mode ON' in t]
print('   pill:', mode or '未出现')

# 3) 双击网页选词(网页区中心避开侧栏:侧栏约从 x=975 起,点 x=700)
print('== 双击选词')
click(700, 480, 0.6)
sh("uitest uiInput click 700 480", tmo=25)
time.sleep(0.25)
sh("uitest uiInput click 700 480", tmo=25)
time.sleep(4)

out = sh("hilog -x", tmo=60)
open(EV + r"\v5_hilog.txt", "w", encoding="utf-8").write(out)
for needle, name in [
    ('AgentSidePanel mounted', '侧栏挂载'),
    ('selection captured', 'A 选区捕获'),
    ('auto-attached', 'C tab 附加'),
    ('chat mode loaded', 'B 模式载入'),
]:
    hits = [l.split('JSAPP: ')[-1] for l in out.splitlines() if needle in l and 'JSAPP: ' in l]
    print('%-10s: %s' % (name, hits[-1] if hits else '未见'))
# chip 视觉证据
ts = dump_texts('v5_sel.json')
print('已选 chip:', [t for t, _ in ts if '已选' in t] or '未见')
