"""P33 D 收尾:冷启动→等弹窗→立即点→验证 dismissed/marked→重启验证不再弹"""
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


print('== 冷启动应用')
sh("aa force-stop com.browseros.kaihong")
time.sleep(2)
sh("aa start -a EntryAbility -b com.browseros.kaihong")

print('== 轮询等弹窗(最多15s)')
btn = None
for i in range(10):
    time.sleep(1.5)
    texts = get_texts('d_cycle_%d.json' % i)
    for t, b in texts:
        if t == '知道了' and b and re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', str(b)):
            btn = b
            break
    if btn:
        break
    print('   第%d轮:未见弹窗' % i)
if not btn:
    print('FAIL: 弹窗未出现')
    sys.exit(1)
print('== 弹窗出现 bounds:', btn)
xs = [int(v) for v in re.findall(r'\d+', btn)]
cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
_, o = sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
print('== 点击', cx, cy, '->', o)
time.sleep(2.5)

texts2 = get_texts('d_after_ok.json')
gone = not any(t == '知道了' for t, _ in texts2)
print('== 弹窗消失:', gone)

_, out = sh("hilog -x", tmo=60)
dism = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'overlay dismissed' in l]
mark = [l.split('JSAPP: ')[-1] for l in out.splitlines() if 'overlay marked' in l]
print('== dismissed:', dism[-1] if dism else 'NONE')
print('== marked:', mark[-1] if mark else 'NONE')

if gone and dism and mark:
    print('== 重启验证不再弹')
    sh("aa force-stop com.browseros.kaihong")
    time.sleep(2)
    sh("aa start -a EntryAbility -b com.browseros.kaihong")
    time.sleep(9)
    _, out2 = sh("hilog -x", tmo=60)
    aft = [l.split('JSAPP: ')[-1] for l in out2.splitlines() if 'already shown' in l]
    texts3 = get_texts('d_relaunch.json')
    still = any(t == '知道了' for t, _ in texts3)
    print('== already-shown 日志:', aft[-1] if aft else 'NONE', '| 弹窗再现(应False):', still)
    print('\nRESULT D:', 'PASS' if (aft and not still) else 'PARTIAL')
else:
    print('\nRESULT D: FAIL(点击未生效)')
