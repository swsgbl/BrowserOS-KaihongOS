# -*- coding: utf-8 -*-
"""新 dump 的属性值是字符串 'true'/'false'？看一个 Text 节点样例，然后正确遍历。"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_fresh.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

found = [0]

def walk(node):
    a = node.get('attributes') or {}
    t = a.get('text')
    hint = a.get('hint')
    bd = parse(a.get('bounds', ''))
    # text/hint 可能是 None
    ts = str(t) if t else ''
    hs = str(hint) if hint else ''
    if bd and (ts or hs):
        c = ((bd[0]+bd[2])//2, (bd[1]+bd[3])//2)
        print(f"{c} | {ts[:30]} | {hs[:40]}")
        found[0] += 1
    for ch in (node.get('children') or []):
        walk(ch)

walk(data)
print('total:', found[0])
