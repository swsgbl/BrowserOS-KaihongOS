"""P33 A/B/C 设备验证 v3(btn7=[1269,185] 是侧栏开关)"""
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


step('0) 拉起应用前台')
sh("aa start -a EntryAbility -b com.browseros.kaihong")
time.sleep(3.5)

step('1) 开 Agent 侧栏(btn7 @1284,200)')
click(1284, 200, 2.5)
ts = dump_texts('v3_panel.json')
mode = [t for t, _ in ts if 'Mode ON' in t]
print('   pill:', mode or '未出现')
if not mode:
    print('   FAIL')
    sys.exit(1)

# ---------- C 先验(此时还没动选区) ----------
step('2) C: 附加 tab chip 检查')
att = [t for t, _ in ts if 'Example Domain' in t]
print('   chip 候选:', att[:2])
_, out = sh("hilog -x", tmo=60)
auto = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'auto-attached' in l]
print('   auto-attach 日志:', auto[-1] if auto else 'NONE')

# ---------- B ----------
step('3) B: 切 chat 模式')
b = None
for t, bb in ts:
    if 'Agent Mode ON' in t:
        b = bb
        break
if b:
    xs = [int(v) for v in re.findall(r'\d+', b)]
    click((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2, 2)
    ts = dump_texts('v3_chat.json')
    print('   Chat pill:', [t for t, _ in ts if 'Chat Mode ON' in t] or '未出现!')
    _, out = sh("hilog -x", tmo=60)
    cm = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'chat mode' in l]
    print('   模式日志(最近2):', cm[-2:])
else:
    print('   无 Agent Mode pill(状态:', [t for t, _ in ts if 'Mode' in t], ')')

# ---------- A ----------
step('4) A: 网页双击选词→chip')
click(700, 480, 0.8)
click(700, 480, 0.1)
time.sleep(3)
ts = dump_texts('v3_sel.json')
sel = [t for t, _ in ts if '已选' in t]
print('   已选 chip:', sel or '未出现')
_, out = sh("hilog -x", tmo=60)
cap = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'selection captured' in l]
print('   capture 日志:', cap[-1] if cap else 'NONE')
