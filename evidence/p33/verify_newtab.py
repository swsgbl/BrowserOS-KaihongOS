import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p33"


def sh(cmd, timeout=90):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def recv(remote, local):
    subprocess.run([HDC, '-t', T, 'file', 'recv', remote, EV + '\\' + local],
                   capture_output=True, text=True, timeout=60)


# 清 ultrafast 持久化(先看路径)
print(sh('ls /data/app/el2/100/base/com.browseros.kaihong/haps/entry/preferences/ 2>/dev/null || ls /data/app/el2/100/base/com.browseros.kaihong/haps/entry/ | head'))
sh('rm -f /data/app/el2/100/base/com.browseros.kaihong/haps/entry/preferences/ultrafast_store* 2>/dev/null')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
sh('uitest dumpLayout -p /data/local/tmp/z.json')
recv('/data/local/tmp/z.json', 'acc_newtab.json')
sh('snapshot_display -f /data/local/tmp/z.jpeg')
recv('/data/local/tmp/z.jpeg', 'acc_newtab.jpeg')

lay = open(EV + r'\acc_newtab.json', encoding='utf-8', errors='replace').read()
print('What are your agents :', 'What are your agents' in lay)
print('right now? :', 'right now?' in lay)
print('Ultrafast :', 'Ultrafast' in lay)
print('10× fewer tokens :', '10× fewer tokens' in lay)
print('Request early access :', 'Request early access' in lay)
print('BrowserOS neo (badge) :', 'BrowserOS neo' in lay)
