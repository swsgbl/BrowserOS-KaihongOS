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


def bc(b):
    m = re.findall(r'\d+', b)
    return ((int(m[0]) + int(m[2])) // 2, (int(m[1]) + int(m[3])) // 2) if len(m) >= 4 else None


def find(j, needle):
    res = []

    def w(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or n
        t = a.get('text', '') or ''
        if needle in t:
            res.append((t[:36], a.get('bounds', '')))
        for c in (n.get('children') or []):
            w(c)
    w(j)
    return res


# dismiss dialog (拒绝)
sh('uinput -T -c 684 539')
time.sleep(2)

j = dump('p59_l_nlp2.json')
if j:
    dlg = find(j, '敏感操作')
    print('dialog still?', bool(dlg))
    hits = find(j, '描述') + find(j, '发送') + find(j, 'agnes')
    for h in hits[:8]:
        print(h)
