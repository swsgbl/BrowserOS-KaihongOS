import json, re, sys
sys.stdout.reconfigure(encoding='utf-8')
lay = open(r'D:\BrowserOS - KaihongOS\evidence\p45\after_prop.json', encoding='utf-8', errors='replace').read()
print('len:', len(lay))
texts = [t for t in re.findall(r'"text":"([^"]{1,26})"', lay) if t]
print('TEXTS:', texts[:16])
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


for a in walk(data):
    if a.get('type') == 'Button':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and int(m.group(1)) < 250 and int(m.group(2)) < 400:
            print('BTN', b, 'a11y=', repr((a.get('accessibilityText') or '')[:35]))
print('hero present:', 'What should your agent' in lay)
