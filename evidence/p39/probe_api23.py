import re, sys
sys.stdout.reconfigure(encoding='utf-8')
lay = open(r'D:\BrowserOS - KaihongOS\attic\api23_v1.json', encoding='utf-8', errors='replace').read()
for probe in ['BrowserOS', 'What should your agent', 'working on', 'next?', 'Ultrafast', 'agnes', '未配置', 'about:blank', '输入URL']:
    print(probe, ':', probe in lay)
texts = re.findall(r'"text":"([^"]{1,24})"', lay)
print('TEXTS:', [t for t in texts if t][:18])
# 左列小 Image（图标渲染结构在位）
import json
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
imgs = []
for a in walk(data):
    if a.get('type') == 'Image':
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if m and (int(m.group(4)) - int(m.group(2))) <= 30 and int(m.group(2)) > 60:
            imgs.append(b)
print('small images:', imgs[:8])
