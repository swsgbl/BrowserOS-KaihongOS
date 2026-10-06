# -*- coding: utf-8 -*-
"""设置面板 Column [278,275][1322,458]：dump 直接子节点 bounds（Text头+3个TextInput+保存行）"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

def walk(node):
    a = node.get('attributes', {}) or {}
    bd = parse(a.get('bounds', ''))
    if bd and bd == (278, 275, 1322, 458):
        def dump(n, d):
            aa = n.get('attributes', {}) or {}
            b = parse(aa.get('bounds', ''))
            c = f"({(b[0]+b[2])//2},{(b[1]+b[3])//2})" if b else ''
            print('  '*d, aa.get('type', '?'), '|', str(aa.get('text', ''))[:20], '|', str(aa.get('hint', ''))[:36], '|', b, '| c=', c)
            for ch in (n.get('children') or []):
                dump(ch, d+1)
        dump(node, 0)
        return True
    for c in (node.get('children') or []):
        if walk(c):
            return True
    return False

walk(data)
