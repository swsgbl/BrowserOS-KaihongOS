# -*- coding: utf-8 -*-
"""递归 dump 所有无 bounds 的 Text 节点文本"""
import json, io, sys, re

PATH = r'D:\BrowserOS - KaihongOS\p2_layout.json'
with io.open(PATH, encoding='utf-8') as f:
    data = json.load(f)

out = []

def walk(node, depth):
    a = node.get('attributes', {}) or {}
    t = a.get('text', '')
    bd = a.get('bounds', '')
    ty = a.get('type', '')
    if t:
        m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(bd))
        coord = ((int(m.group(1))+int(m.group(3)))//2, (int(m.group(2))+int(m.group(4)))//2) if m else None
        out.append(('  '*depth) + f"[{ty}] {t} @ {coord}")
    for c in (node.get('children') or []):
        walk(c, depth+1)

walk(data, 0)
io.open(r'D:\BrowserOS - KaihongOS\p2_ui_tree.txt', 'w', encoding='utf-8').write('\n'.join(out))
print('nodes with text:', len(out))
print('\n'.join(out[:60]))
