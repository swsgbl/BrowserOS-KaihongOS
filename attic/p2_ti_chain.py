# -*- coding: utf-8 -*-
"""打印'创建新代理'Text 的兄弟 TextInput 及各自祖先 bounds，向上最多5层"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

# 找到所有 TextInput 节点及其祖先链
tis = []

def walk(node, chain):
    a = node.get('attributes', {}) or {}
    ty = str(a.get('type', ''))
    if ty == 'TextInput':
        tis.append(list(chain) + [node])
    for c in (node.get('children') or []):
        walk(c, chain + [node])

walk(data, [])

for chain in tis:
    hint = chain[-1].get('attributes', {}).get('hint', '')
    print('=== TextInput', hint)
    for anc in reversed(chain[-6:-1]):
        aa = anc.get('attributes', {})
        print('   ', aa.get('type', '?'), aa.get('bounds', ''))
