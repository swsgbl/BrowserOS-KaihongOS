# -*- coding: utf-8 -*-
"""列出带 bounds 的所有节点：type/text/hint/clickable"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

out = []

def walk(node, depth):
    a = node.get('attributes', {}) or {}
    ty = str(node.get('type', ''))
    t = str(a.get('text', ''))
    hint = str(a.get('hint', ''))
    bd = str(a.get('bounds', ''))
    clickable = str(a.get('clickable', ''))
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', bd)
    if m and (t or hint or clickable == 'true'):
        x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
        out.append(f"{ty} | {t[:24]} | hint={hint[:24]} | click={clickable} | center={(x1+x2)//2},{(y1+y2)//2}")
    for c in (node.get('children') or []):
        walk(c, depth+1)

walk(data, 0)
print('\n'.join(out[:50]))
print('total', len(out))
