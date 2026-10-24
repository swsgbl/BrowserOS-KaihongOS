import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
F = "/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json"
CMDS = [
    "aa force-stop com.browseros.kaihong",
    "cat %s | sed 's/\"isOnboardingCompleted\":false/\"isOnboardingCompleted\":true/' > /data/local/tmp/c.json" % F,
    "cp /data/local/tmp/c.json %s" % F,
    "grep -o 'isOnboardingCompleted[^,]*' %s" % F,
    "aa start -a EntryAbility -b com.browseros.kaihong",
]
for c in CMDS:
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=60)
    print('>', c[:60], '\n ', ((r.stdout or '') + (r.stderr or '')).strip()[:120])
time.sleep(7)
subprocess.run([HDC, '-t', T, 'shell', 'uitest dumpLayout -p /data/local/tmp/z.json'], capture_output=True, timeout=90)
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', r'D:\BrowserOS - KaihongOS\attic\api23_v2.json'], capture_output=True, timeout=60)
lay = open(r'D:\BrowserOS - KaihongOS\attic\api23_v2.json', encoding='utf-8', errors='replace').read()
for p in ['What should your agent', 'next?', 'Ultrafast', '输入URL', '未配置', 'BrowserOS neo', 'about:blank']:
    print(p, ':', p in lay)
