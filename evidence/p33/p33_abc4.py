"""P33 A/B/C 验证 v2:hint 不可靠,改用固定坐标(工具栏 ic_agent=倒数第二个图标区)"""
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


def click(cx, cy, wait=1.8):
    sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
    time.sleep(wait)


def step(m):
    print('\n== ' + m, flush=True)


# 底部工具栏 Images(自 abc_toolbar dump): [1429,865]~[1583,882] 一排
# ic_agent 是 'AI 代理侧栏'——按 BrowserShell 源码在 ic_home 之后。工具栏顺序:
# r.1.0.0.1.1.x: search(1375) star?(1400) home?(1429) agent?(1479) menu?(1566)
# [1479,865][1496,882] 猜是 ic_agent。先点它验证(侧栏开了 texts 会变)

step('1) 点工具栏第4图标(猜 ic_agent @1479,873)')
click(1487, 873)
ts = dump_texts('abc_v2_panel.json')
mode = [t for t, _ in ts if 'Mode ON' in t]
print('   Mode pill:', mode or '侧栏未开?')

if not mode:
    step('1b) 换试第3图标 @1437,873')
    click(1437, 873, 2)
    ts = dump_texts('abc_v2_panel2.json')
    mode = [t for t, _ in ts if 'Mode ON' in t]
    print('   Mode pill:', mode or '仍未开')
    if not mode:
        step('1c) 再试 @1563,873(第5)')
        click(1563, 873, 2)
        ts = dump_texts('abc_v2_panel3.json')
        mode = [t for t, _ in ts if 'Mode ON' in t]
        print('   Mode pill:', mode or '仍未开')
        sys.exit(1)

# ---------- B ----------
step('2) B: 切 chat 模式')
b = None
for t, bb in ts:
    if 'Agent Mode ON' in t:
        b = bb
        break
if b:
    xs = [int(v) for v in re.findall(r'\d+', b)]
    click((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2)
    ts = dump_texts('abc_v2_chat.json')
    print('   Chat pill:', [t for t, _ in ts if 'Chat Mode ON' in t] or '未出现!')
else:
    print('   已是 chat? ', [t for t, _ in ts if 'Chat' in t])

# ---------- A ----------
step('3) A: 网页双击选词→等1s轮询→查chip')
click(600, 400, 1)
sh("uitest uiInput click 600 400", tmo=25)
time.sleep(0.25)
sh("uitest uiInput click 600 400", tmo=25)
time.sleep(3)
ts = dump_texts('abc_v2_sel.json')
print('   已选chip:', [t for t, _ in ts if '已选' in t] or '未出现')
_, out = sh("hilog -x", tmo=60)
cap = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'selection captured' in l]
print('   capture 日志:', cap[-1] if cap else 'NONE')

# ---------- C ----------
step('4) C: 附加 tab chip')
print('   attached chip 候选:', [t for t, _ in ts if 'Example' in t][:3])
_, out = sh("hilog -x", tmo=60)
auto = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'auto-attached' in l]
print('   auto-attach 日志:', auto[-1] if auto else 'NONE')
