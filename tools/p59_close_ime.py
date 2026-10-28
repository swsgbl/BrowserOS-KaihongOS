import sys, time, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"

# close IME dialog: Back key via uitest
sh('uitest uiInput keyEvent Back')
time.sleep(1.5)
sh('uitest uiInput keyEvent Back')
time.sleep(1)
out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\p59_l_afterback_key.json'], capture_output=True)
j = json.load(open(EV + '\\p59_l_afterback_key.json', encoding='utf-8'))
txt = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    t = a.get('text', '') or ''
    if t:
        txt.append(t[:26])
    for c in (n.get('children') or []):
        w(c)


w(j)
print(' | '.join(txt[:30]))
