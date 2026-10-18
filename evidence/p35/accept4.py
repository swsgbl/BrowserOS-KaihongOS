import subprocess, sys, time, re
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p35"


def sh(c):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=60)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump(name):
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + '\\' + name],
                   capture_output=True, timeout=60)
    return open(EV + '\\' + name, encoding='utf-8', errors='replace').read()


def input_value(lay):
    for m in re.finditer(r'"type":"TextInput"', lay):
        seg = lay[max(0, m.start() - 600):m.start()]
        t = seg.rfind('"text":"')
        if t >= 0:
            return seg[t + 8:seg.find('"', t + 8)]
    return None


sh('uitest uiInput click 873 501')
time.sleep(0.6)
for i in range(20):
    sh('uitest uiInput keyEvent 2055')
time.sleep(0.5)
r = sh('uitest uiInput inputText 873 501 a@b.co')
print('inputText rc:', r[:40])
time.sleep(1)
lay = dump('a3_s4.json')
print('INPUT=', repr(input_value(lay)))
