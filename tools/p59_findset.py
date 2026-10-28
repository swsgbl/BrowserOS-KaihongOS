import sys, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
print('dump:', m.group(1) if m else out[:200])
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1),
                r'D:\BrowserOS - KaihongOS\evidence\p59\p59_l_now.json'], capture_output=True)
j = json.load(open(r'D:\BrowserOS - KaihongOS\evidence\p59\p59_l_now.json', encoding='utf-8'))
res = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    t = a.get('text', '') or ''
    if t == '设置' or '技能' in t or 'Skills' in t:
        res.append((t[:20], a.get('bounds', '')))
    for c in (n.get('children') or []):
        w(c)


w(j)
print(json.dumps(res, ensure_ascii=False))
