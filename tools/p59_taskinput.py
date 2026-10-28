import sys, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\p59_l_nlp.json'], capture_output=True)
j = json.load(open(EV + '\\p59_l_nlp.json', encoding='utf-8'))
res = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    t = a.get('text', '') or ''
    if t and ('描述' in t or 'Enter' in t or '发送' in t or '目标' in t or '代理' in t or 'agnes' in t.lower()):
        res.append((t[:36], a.get('bounds', ''), (a.get('id', '') or '')[:20]))
    for c in (n.get('children') or []):
        w(c)


w(j)
for r in res[:14]:
    print(r)
