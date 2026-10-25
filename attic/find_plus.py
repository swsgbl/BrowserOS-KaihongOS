import json, re, sys
sys.stdout.reconfigure(encoding='utf-8')
lay = open(r'D:\BrowserOS - KaihongOS\evidence\p45\center.json', encoding='utf-8', errors='replace').read()
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


# Find all Image and Button elements in the left area (x < 350)
print('=== All elements x<350, y 100-500 ===')
for a in walk(data):
    t = a.get('type') or ''
    if t in ('Image', 'Button'):
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            if x1 < 350 and 100 < y1 < 500:
                w = x2 - x1
                h = y2 - y1
                cx = (x1 + x2) // 2
                print('%s %s (%dx%d) center_x=%d a11y=%r' % (t, b, w, h, cx, (a.get('accessibilityText') or '')[:20]))

# Also check window bounds
for a in walk(data):
    if a.get('type') == 'ContainerModal':
        print('\nwindow:', a.get('bounds'))
        break
