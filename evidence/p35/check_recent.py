import json, re, sys
sys.stdout.reconfigure(encoding='utf-8')
lay = open(r'D:\BrowserOS - KaihongOS\evidence\p35\acc35_dash.json', encoding='utf-8', errors='replace').read()
data = json.loads(lay)


def walk(n):
    if isinstance(n, dict):
        a = n.get('attributes')
        if isinstance(a, dict):
            yield a
        for c in (n.get('children') or []):
            yield from walk(c)
    elif isinstance(n, list):
        for c in n:
            yield from walk(c)


# 找含域名特征的 Text（.com/.cn/.org 或常见站名）
doms = []
for a in walk(data):
    t = a.get('text') or ''
    if re.search(r'\.(com|cn|org|net|io|dev)\b', t) or t in ('example', 'iana', 'gitee', 'neverssl', 'huawei', 'openharmony'):
        doms.append((t[:30], a.get('bounds')))
print('domain-ish texts:', doms[:12])
# 输入框与 provider 区域附近的所有 Text（y 350-650）
print('--- texts y350-680 ---')
for a in walk(data):
    if a.get('type') != 'Text':
        continue
    b = str(a.get('bounds', ''))
    m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
    if m and 350 <= int(m.group(2)) <= 680:
        t = a.get('text') or ''
        if t:
            print(b, repr(t[:40]))
