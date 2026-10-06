# -*- coding: utf-8 -*-
"""从 dump 找可点击节点 bounds（Button/Stage 等，含'查看代理'）"""
import json, io, re, sys

PATH = r'D:\BrowserOS - KaihongOS\p2_layout.json'
with io.open(PATH, encoding='utf-8') as f:
    data = json.load(f)

target = sys.argv[1] if len(sys.argv) > 1 else '查看代理'
results = []

def walk(node):
    a = node.get('attributes', {}) or {}
    t = str(a.get('text', ''))
    ty = str(a.get('type', ''))
    bd = str(a.get('bounds', ''))
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', bd)
    if m and (target in t or target in ty):
        x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
        results.append((t[:40], ty, (x1+x2)//2, (y1+y2)//2, x1, y1, x2, y2))
    for c in (node.get('children') or []):
        walk(c)

walk(data)
for r in results:
    print(r)
