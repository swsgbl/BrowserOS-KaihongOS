"""P33 A/B/C 完整链验证"""
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


def click_b(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
    _, o = sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
    time.sleep(1.8)
    return o


def find_text(texts, needle):
    for t, b in texts:
        if needle in t and b and re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', str(b)):
            return t, b
    return None, None


def step(m):
    print('\n== ' + m, flush=True)


step('1) 启动应用')
sh("aa start -a EntryAbility -b com.browseros.kaihong")
time.sleep(4)
texts = get_texts('abc_1_main.json')
print('   前10:', [t for t, _ in texts[:10]])

# 2) 找 Agent 侧栏开关(工具栏图标按钮,description 含 Agent/agent)
step('2) 找侧栏开关')
# dump 里 hint/description 也要查——改查全部含 Agent 的 text
t, b = find_text(texts, 'Agent')
if not b:
    # 尝试从完整 JSON 找 description 含 agent 的 Image 按钮
    sh("uitest dumpLayout -p /data/local/tmp/p33.json", tmo=60)
    hdc("file", "recv", "/data/local/tmp/p33.json", EV + "\\abc_2_full.json", tmo=30)
    raw = open(EV + "\\abc_2_full.json", encoding='utf-8', errors='replace').read()
    j = json.loads(raw)
    found = []
    def walk2(n, path):
        a = n.get('attributes') or {}
        d = (a.get('description') or '') + (a.get('text') or '') + (a.get('id') or '')
        if 'agent' in d.lower():
            found.append((path, a.get('type'), a.get('description') or a.get('text'), a.get('bounds')))
        for ch in (n.get('children') or []):
            walk2(ch, path + '.' + str(len(found)))
    if isinstance(j, dict):
        walk2(j, 'r')
    print('   agent 相关节点:', found[:8])
    if found:
        b = found[0][3]
if b:
    print('   点击侧栏开关', b)
    click_b(b)
    time.sleep(1)
    texts = get_texts('abc_3_panel.json')
    print('   侧栏 texts:', [t for t, _ in texts if 'Agent' in t or 'Mode' in t or '代理' in t][:10])
else:
    print('   未找到侧栏开关!')
