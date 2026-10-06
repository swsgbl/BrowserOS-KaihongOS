# -*- coding: utf-8 -*-
"""dump 节点全属性样例：定位 Button 与 bounds 的真实字段名"""
import json, io

PATH = r'D:\BrowserOS - KaihongOS\p2_layout.json'
with io.open(PATH, encoding='utf-8') as f:
    data = json.load(f)

count = 0

def walk(node, depth):
    global count
    a = node.get('attributes', {}) or {}
    t = str(a.get('text', ''))
    if ('Button' in str(a)) or '代理' in t or '新建' in t:
        print('  '*depth, json.dumps(a, ensure_ascii=False)[:400])
        count += 1
        if count > 15:
            raise SystemExit
    for c in (node.get('children') or []):
        walk(c, depth+1)

try:
    walk(data, 0)
except SystemExit:
    pass
print('shown', count)
