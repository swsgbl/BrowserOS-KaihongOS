"""P33 D 最终验证:重启→弹窗→点知道了→hilog落盘→重启不再弹"""
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


def dump_text(name):
    sh("uitest dumpLayout -p /data/local/tmp/p33.json", tmo=60)
    hdc("file", "recv", "/data/local/tmp/p33.json", EV + "\\" + name, tmo=30)
    try:
        c = open(EV + "\\" + name, encoding='utf-8', errors='replace').read()
        j = json.loads(c)
        texts = []
        def walk(n):
            a = n.get('attributes') or {}
            if a.get('text'):
                texts.append((a['text'], a.get('bounds')))
            for ch in (n.get('children') or []):
                walk(ch)
        if isinstance(j, dict):
            walk(j)
        return texts
    except Exception:
        return []


def find(texts, needle):
    for t, b in texts:
        if needle in t and b and re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', str(b)):
            return t, str(b)
    return None, None


def center(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    return (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2


def click(cx, cy):
    _, out = sh("uitest uiInput click %d %d" % (cx, cy), tmo=25)
    print('   click(%d,%d) -> %s' % (cx, cy, out.strip() or 'ok'))
    time.sleep(2.2)


def step(m):
    print('\n== ' + m, flush=True)


step('1) 冷启动')
sh("aa force-stop com.browseros.kaihong")
time.sleep(1.5)
sh("aa start -a EntryAbility -b com.browseros.kaihong")
print('   等待 9s(启动+5s延迟)')
time.sleep(9)

step('2) 找弹窗并点「知道了」')
texts = dump_text('d_final_before.json')
t, b = find(texts, '知道了')
if not b:
    print('   弹窗未出现! texts 前20:', [x[0] for x in texts[:20]])
    sys.exit(1)
print('   按钮 bounds:', b)
click(*center(b))

step('3) 验证 hilog dismissed+marked')
_, out = sh("hilog -x", tmo=40)
dism = [l for l in out.splitlines() if 'overlay dismissed' in l]
mark = [l for l in out.splitlines() if 'overlay marked' in l]
print('   dismissed:', dism[-1] if dism else 'NONE')
print('   marked:', mark[-1] if mark else 'NONE')

step('4) 重启验证不再弹')
sh("aa force-stop com.browseros.kaihong")
time.sleep(1.5)
sh("aa start -a EntryAbility -b com.browseros.kaihong")
time.sleep(9)
_, out = sh("hilog -x", tmo=40)
after = [l for l in out.splitlines() if 'overlay' in l and ('already shown' in l or 'pending' in l)]
print('   重启后 overlay 日志(应 already shown):', after[-1] if after else 'NONE')
texts2 = dump_text('d_final_after.json')
gone = not any('知道了' in t for t, _ in texts2)
print('   重启后弹窗已消失:', gone)
print('\nRESULT: D', 'PASS' if (dism and mark and gone) else 'PARTIAL(见日志)')
