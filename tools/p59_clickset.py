import sys, time, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"


def texts():
    out = sh('uitest dumpLayout')
    m = re.search(r'saved to:(\S+)', out)
    subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\p59_l_tmp.json'], capture_output=True)
    j = json.load(open(EV + '\\p59_l_tmp.json', encoding='utf-8'))
    res = []

    def w(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or n
        t = a.get('text', '') or ''
        if t:
            res.append(t[:24])
        for c in (n.get('children') or []):
            w(c)
    w(j)
    return res


before = texts()
print('BEFORE sample:', ' | '.join(before[:12]))
sh('uinput -T -c 69 611')
time.sleep(3)
after = texts()
print('AFTER sample:', ' | '.join(after[:14]))
new = [t for t in after if t not in before]
print('NEW:', ' | '.join(new[:20]))
