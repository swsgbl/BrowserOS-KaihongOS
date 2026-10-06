# -*- coding: utf-8 -*-
"""children 属性名可能不同。dump 根节点结构真实键名。"""
import json, io

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def show(n, d):
    if d > 4:
        return
    print('  '*d, type(n).__name__, list(n.keys()) if isinstance(n, dict) else str(n)[:60])
    if isinstance(n, dict):
        for k in ('children', 'child', 'nodes'):
            v = n.get(k)
            if isinstance(v, list):
                for c in v[:3]:
                    show(c, d+1)

show(data, 0)
