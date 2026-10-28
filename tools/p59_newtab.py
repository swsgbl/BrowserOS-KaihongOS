import sys, time, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
time.sleep(1)
out = sh('uitest dumpLayout')
m = re.search(r'saved to:(\S+)', out)
subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\p59_l_tabs.json'], capture_output=True)
j = json.load(open(EV + '\\p59_l_tabs.json', encoding='utf-8'))
res = []


def w(n):
    if not isinstance(n, dict):
        return
    a = n.get('attributes') or n
    t = a.get('text', '') or ''
    bid = (a.get('id', '') or '')
    if '新建标签页' in t or 'new' in bid.lower() or 'plus' in bid.lower() or t.strip() == '+':
        res.append((t[:30], a.get('bounds', ''), bid[:24]))
    for c in (n.get('children') or []):
        w(c)


w(j)
print(json.dumps(res[:8], ensure_ascii=False))
