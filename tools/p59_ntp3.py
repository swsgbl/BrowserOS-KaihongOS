import sys, time, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
time.sleep(0.5)
out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\p59_l_ntp3.json'], capture_output=True)
j = json.load(open(EV + '\\p59_l_ntp3.json', encoding='utf-8'))
res = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    t = a.get('text', '') or ''
    if t and ('查看代理' in t or '导入登录' in t or '开始' in t or '跳过' in t or '使用' in t):
        res.append((t[:30], a.get('bounds', '')))
    for c in (n.get('children') or []):
        w(c)


w(j)
for r in res[:10]:
    print(r)
