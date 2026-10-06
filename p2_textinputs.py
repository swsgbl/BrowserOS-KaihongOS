# -*- coding: utf-8 -*-
"""TextInput 节点定位：hint + bounds"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

out = []

def walk(node):
    a = node.get('attributes', {}) or {}
    ty = str(a.get('type', ''))
    hint = str(a.get('hint', ''))
    bd = str(a.get('bounds', ''))
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', bd)
    cx = cy = -1
    if m:
        x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
        cx, cy = (x1+x2)//2, (y1+y2)//2
    if ty == 'TextInput' or hint in ('代理名称', '目标URL', '任务描述'):
        out.append((ty, hint, cx, cy))
    for c in (node.get('children') or []):
        walk(c)

walk(data)
for o in out:
    print(o)
