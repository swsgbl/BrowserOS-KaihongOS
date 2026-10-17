"""P33 D 最后一击:直接点当前屏幕上的「知道了」并立即验证"""
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


# 1. 找按钮
texts = get_texts('d_strike_before.json')
btn = None
for t, b in texts:
    if t == '知道了' and b:
        btn = b
        break
if not btn:
    print('弹窗未在屏幕上,退出')
    sys.exit(1)
xs = [int(v) for v in re.findall(r'\d+', btn)]
cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
print('button at', btn, '-> click', cx, cy)

# 2. 点击(uiInput keyEvent 方式兜底再来一次普通 click)
_, o = sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
print('click rc:', o)
time.sleep(2.5)

# 3. 验证弹窗消失 + hilog
texts2 = get_texts('d_strike_after.json')
gone = not any(t == '知道了' for t, _ in texts2)
print('弹窗消失:', gone)

_, out = sh("hilog -x", tmo=60)
dism = [l for l in out.splitlines() if 'overlay dismissed' in l or 'overlay marked' in l]
print('dismissed/marked:', dism[-2:] if dism else 'NONE')

# 4. 若仍没反应,试 keyEvent Tab+Enter
if not gone:
    print('尝试 keyEvent 兜底...')
    for _ in range(6):
        sh("uitest uiInput keyEvent 2042")  # TAB
        time.sleep(0.4)
    sh("uitest uiInput keyEvent 2049")  # ENTER
    time.sleep(2.5)
    texts3 = get_texts('d_strike_after2.json')
    gone2 = not any(t == '知道了' for t, _ in texts3)
    print('keyEvent 后弹窗消失:', gone2)
