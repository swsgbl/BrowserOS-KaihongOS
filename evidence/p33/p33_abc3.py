"""P33 A/B/C 设备验证
A: 打开网页→选中文本→侧栏出现「已选 N 字」chip
B: 侧栏 ChatMode pill 切换 chat/agent + Preferences 持久化(重启保持)
C: 侧栏自动出现附加 tab chip;点 X 消失
"""
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


def find_acc(j, needle):
    """按 accessibilityText/description/text 找节点 bounds"""
    hits = []
    def walk(n):
        a = n.get('attributes') or {}
        hay = ((a.get('text') or '') + ' ' + (a.get('description') or '') + ' ' + (a.get('id') or ''))
        if needle in hay and a.get('bounds') and re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', str(a.get('bounds'))):
            hits.append(a)
        for ch in (n.get('children') or []):
            walk(ch)
    if isinstance(j, dict):
        walk(j)
    return hits


def center(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    return (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2


def click_b(b):
    cx, cy = center(b)
    sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
    time.sleep(1.8)


def step(m):
    print('\n== ' + m, flush=True)


# ---------- 0) 前置:启动应用,开一个网页 tab ----------
step('0) 启动并打开网页 tab')
sh("aa start -a EntryAbility -b com.browseros.kaihong")
time.sleep(4)
j = dump('abc_main.json')
ts = texts_of(j)
# 书签栏有 Example Domain——点它开网页
b = None
for t, bb in ts:
    if 'Example Domain' in t:
        b = bb
        break
if b:
    click_b(b)
    time.sleep(4)
    print('   网页 tab 已打开')
else:
    print('   未找到书签入口,tolerant 继续')

# ---------- 1) 开 Agent 侧栏 ----------
step('1) 打开 Agent 侧栏')
j = dump('abc_toolbar.json')
hits = find_acc(j, 'AI 代理侧栏')
if not hits:
    print('   FAIL: 找不到侧栏按钮')
    sys.exit(1)
click_b(hits[0]['bounds'])
time.sleep(2)
j = dump('abc_panel_open.json')
ts = texts_of(j)
mode = [t for t, _ in ts if 'Mode ON' in t]
print('   侧栏已开,模式 pill:', mode)

# ---------- 2) B: 切到 chat 模式 ----------
step('2) B: 点击 pill 切 chat 模式')
b = None
for t, bb in ts:
    if 'Agent Mode ON' in t:
        b = bb
        break
if b:
    click_b(b)
    time.sleep(1.5)
    j = dump('abc_chat_mode.json')
    ts2 = texts_of(j)
    chat = [t for t, _ in ts2 if 'Chat Mode ON' in t]
    print('   Chat Mode pill:', chat or '未出现!')
else:
    print('   Agent Mode pill 未找到(可能已在 chat)')

# ---------- 3) A: 网页选中文本 → chip ----------
step('3) A: 网页里双击选词(模拟选中)')
# 切回网页:点页面中央(侧栏在右,网页在左)
sh("uitest uiInput click 600 450", tmo=25)
time.sleep(1)
# 用双击选中(uitest 无 doubleClick,连续两次 click)
sh("uitest uiInput click 600 450", tmo=25)
time.sleep(0.3)
sh("uitest uiInput click 600 450", tmo=25)
time.sleep(3)  # 等 1s 轮询
j = dump('abc_sel_chip.json')
ts3 = texts_of(j)
sel = [t for t, _ in ts3 if '已选' in t]
print('   选中 chip:', sel or '未出现')
_, out = sh("hilog -x", tmo=60)
cap = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'selection captured' in l]
print('   capture 日志:', cap[-1] if cap else 'NONE')

# ---------- 4) C: 附加 tab chip ----------
step('4) C: 检查附加 tab chip')
att = [t for t, _ in ts3 if 'Example Domain' in t]
# chip 应显示 tab 标题
print('   附加 chip 候选:', att[:3])
_, out = sh("hilog -x", tmo=60)
auto = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'auto-attached' in l]
print('   auto-attach 日志:', auto[-1] if auto else 'NONE')
