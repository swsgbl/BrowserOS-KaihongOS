# -*- coding: utf-8 -*-
"""找 NeoDashboard 的 TextInput(bounds) 与关键按钮中心坐标"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

results = []

def walk(node):
    a = node.get('attributes', {}) or {}
    t = str(a.get('text', ''))
    hint = str(a.get('hint', ''))
    ty = str(node.get('type', ''))
    bd = str(a.get('bounds', ''))
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', bd)
    if m:
        x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
        cx, cy = (x1+x2)//2, (y1+y2)//2
        if 'TextInput' in ty or hint or '创建' in t or 'LLM' in t or '返回' in t:
            results.append((ty[:20], t[:20], hint[:30], cx, cy))

for c in data.get('children') or []:
    walk(c)

for r in results:
    print(r)
