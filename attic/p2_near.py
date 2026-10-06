# -*- coding: utf-8 -*-
"""找'创建新代理'文本附近结构：从该 Text 节点向上打印兄弟"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

hits = []

def walk(node, parents):
    a = node.get('attributes', {}) or {}
    t = str(a.get('text', ''))
    if '创建新代理' in t or 'LLM 设置' in t:
        hits.append((node, list(parents)))
    for c in (node.get('children') or []):
        walk(c, parents + [node])

walk(data, [])
print('hits:', len(hits))
for node, parents in hits:
    print('=== target:', node.get('attributes', {}).get('text'))
    for p in reversed(parents[:3]):
        pa = p.get('attributes', {})
        print('  parent:', pa.get('type'), pa.get('bounds'))
        for ch in (p.get('children') or []):
            ca = ch.get('attributes', {})
            print('    child:', ca.get('type'), ca.get('text', '')[:20], ca.get('hint', '')[:30], ca.get('bounds'))
