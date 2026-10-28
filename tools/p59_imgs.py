import sys, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\p59_l_img.json'], capture_output=True)
j = json.load(open(EV + '\\p59_l_img.json', encoding='utf-8'))
res = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    ty = (a.get('type', '') or '')
    b = a.get('bounds', '')
    mm = re.findall(r'\d+', b)
    if len(mm) >= 4 and ty in ('Image', 'Button'):
        x1, y1, x2, y2 = map(int, mm[:4])
        if y1 < 200 and x1 < 560:
            res.append((ty, b, (a.get('id', '') or '')[:26]))
    for c in (n.get('children') or []):
        w(c)


w(j)
for r in res[:16]:
    print(r)
