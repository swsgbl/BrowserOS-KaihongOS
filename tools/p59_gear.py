import sys, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1),
                r'D:\BrowserOS - KaihongOS\evidence\p59\p59_l_tmp3.json'], capture_output=True)
j = json.load(open(r'D:\BrowserOS - KaihongOS\evidence\p59\p59_l_tmp3.json', encoding='utf-8'))
res = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    t = a.get('text', '') or ''
    if t.strip() in ('⚙', '◀', '▶', '☰', '⋮') or 'skill' in t.lower():
        res.append((t.strip()[:8], a.get('bounds', ''), a.get('id', '')[:20]))
    for c in (n.get('children') or []):
        w(c)


w(j)
print(json.dumps(res, ensure_ascii=False))
