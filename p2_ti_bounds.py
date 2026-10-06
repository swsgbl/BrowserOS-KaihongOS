# -*- coding: utf-8 -*-
"""TextInput 的 bounds 在父节点：打印 TextInput 父链 bounds"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def parse_bd(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    if m:
        x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
        return (x1, y1, x2, y2, (x1+x2)//2, (y1+y2)//2)
    return None

out = []

def walk(node, parent_bd):
    a = node.get('attributes', {}) or {}
    ty = str(a.get('type', ''))
    hint = str(a.get('hint', ''))
    own = parse_bd(a.get('bounds', ''))
    eff = own or parent_bd
    if ty == 'TextInput':
        out.append((hint, eff))
    for c in (node.get('children') or []):
        walk(c, eff)

walk(data, None)
for o in out:
    print(o)
