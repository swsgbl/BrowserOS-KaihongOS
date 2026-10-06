# -*- coding: utf-8 -*-
"""全递归：找 TextInput 节点(hint)与创建按钮，输出中心坐标"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

out = []

def walk(node):
    a = node.get('attributes', {}) or {}
    ty = str(a.get('type', ''))
    t = str(a.get('text', ''))
    hint = str(a.get('hint', ''))
    bd = str(a.get('bounds', ''))
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', bd)
    if m:
        x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
        cx, cy = (x1+x2)//2, (y1+y2)//2
        if hint or '创建代理' in t or 'LLM 设置' in t:
            out.append((ty, t[:20], hint[:40], cx, cy))
    for c in (node.get('children') or []):
        walk(c)

walk(data)
print('\n'.join(str(x) for x in out))
