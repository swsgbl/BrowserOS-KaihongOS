import sys, time, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"


def dump(name):
    out = sh('uitest dumpLayout')
    m = re.search(r'saved to:(\S+)', out)
    if not m:
        return None
    subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\' + name], capture_output=True)
    try:
        return json.load(open(EV + '\\' + name, encoding='utf-8'))
    except Exception:
        return None


def texts(j, key=None):
    res = []

    def w(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or n
        t = a.get('text', '') or ''
        if t:
            res.append(t[:26])
        for c in (n.get('children') or []):
            w(c)
    w(j)
    return res


sh('uinput -T -c 1235 695')
time.sleep(2)
j = dump('p59_l_menu.json')
if j:
    print(' | '.join(texts(j)[:40]))
    sh('snapshot_display -f /data/local/tmp/p59_menu_gear.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_menu_gear.jpeg', EV + '\\p59_gear_menu.jpeg'], capture_output=True)
