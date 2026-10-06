# -*- coding: utf-8 -*-
"""递归打印所有 text 节点及 bounds（LLM 相关行也要坐标）"""
import json, io, re, sys

src = sys.argv[1] if len(sys.argv) > 1 else r'D:\BrowserOS - KaihongOS\p2_layout.json'
with io.open(src, encoding='utf-8') as f:
    data = json.load(f)

def walk(node, depth):
    a = node.get('attributes', {}) or {}
    t = str(a.get('text', ''))
    hint = str(a.get('hint', ''))
    bd = str(a.get('bounds', ''))
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', bd)
    cx = cy = -1
    if m:
        x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
        cx, cy = (x1+x2)//2, (y1+y2)//2
    if (t or hint):
        print(f"{'  '*depth}[{cx},{cy}] {t[:40]}{' (hint:' + hint[:30] + ')' if hint else ''}")
    for c in (node.get('children') or []):
        walk(c, depth+1)

walk(data, 0)
