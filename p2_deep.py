# -*- coding: utf-8 -*-
"""深度 dump 应用窗口内 Column 子树（含 TextInput hint 与按钮）"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

out = []

def walk(node, depth):
    a = node.get('attributes', {}) or {}
    ty = str(a.get('type', ''))
    t = str(a.get('text', ''))
    hint = str(a.get('hint', ''))
    bd = str(a.get('bounds', ''))
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', bd)
    cx = cy = -1
    if m:
        x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
        cx, cy = (x1+x2)//2, (y1+y2)//2
    if (t or hint) and m:
        out.append(f"{ty} '{t[:26]}' hint='{hint[:30]}' @ {cx},{cy}")
    for c in (node.get('children') or []):
        walk(c, depth+1)

walk(data, 0)
print('\n'.join(out))
