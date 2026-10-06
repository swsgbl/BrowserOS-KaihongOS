# -*- coding: utf-8 -*-
"""之前的 walk 应该也对该结构有效——检查 '保存' 是否在 children 里被截断。
直接打印全部 text/hint + bounds 一次看全。"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

count = [0]

def walk(node):
    a = node.get('attributes') or {}
    hint = str(a.get('hint', ''))
    t = str(a.get('text', ''))
    bd = parse(a.get('bounds', ''))
    if (hint or t) and bd:
        c = ((bd[0]+bd[2])//2, (bd[1]+bd[3])//2)
        print(f"{c} | {t[:28] or ''} | {hint[:36]}")
        count[0] += 1
    for ch in (node.get('children') or []):
        walk(ch)

walk(data)
print('total labeled+bounds:', count[0])
