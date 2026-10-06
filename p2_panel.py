# -*- coding: utf-8 -*-
"""打印创建面板 Column[278,282][1322,468] 直接子节点与孙节点 bounds"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

target_bd = '[278,282][1322,468]'

def walk(node):
    a = node.get('attributes', {}) or {}
    if str(a.get('bounds', '')) == target_bd:
        print('=== found panel')
        def dump(n, d):
            aa = n.get('attributes', {}) or {}
            print('  '*d, aa.get('type', '?'), '|', aa.get('text', '')[:20], '|', aa.get('hint', '')[:20], '|', aa.get('bounds', ''))
            for c in (n.get('children') or []):
                dump(c, d+1)
        dump(node, 0)
        return True
    for c in (node.get('children') or []):
        if walk(c):
            return True
    return False

walk(data)
