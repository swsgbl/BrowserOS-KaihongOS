# -*- coding: utf-8 -*-
"""inspect node structure: first 2 levels raw"""
import json, io

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def show(node, depth, maxdepth=3):
    if depth > maxdepth:
        return
    ty = node.get('type', '?')
    a = node.get('attributes', {}) or {}
    keys = [k for k in a.keys() if k in ('text', 'hint', 'bounds', 'clickable', 'type')]
    vals = {k: str(a.get(k))[:50] for k in keys}
    print('  '*depth, ty, vals)
    for c in (node.get('children') or [])[:4]:
        show(c, depth+1, maxdepth)

show(data, 0)
