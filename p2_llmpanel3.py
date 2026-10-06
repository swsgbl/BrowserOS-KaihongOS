# -*- coding: utf-8 -*-
""" TextInput 无 bounds → 用全文档按 hint 找 + 从面板父链推算。
改用另一招：面板在 layout 里的 TextInput 按出现顺序，从 dump 的兄弟 Column[278,282][1322,468]（创建面板）
下面找第二个 Column(设置面板)的 bounds。"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

# 找所有 Column 容器（在应用主区内），带 TextInput 子节点的
results = []

def walk(node, parent_bd):
    a = node.get('attributes', {}) or {}
    ty = str(a.get('type', ''))
    own = parse(a.get('bounds', '')) or parent_bd
    if ty == 'Column':
        hints = [str(c.get('attributes', {}).get('hint', '')) for c in (node.get('children') or []) if str(c.get('attributes', {}).get('type', '')) == 'TextInput']
        if any('API' in h or 'Key' in h for h in hints):
            if own:
                results.append((own, hints))
    for c in (node.get('children') or []):
        walk(c, own)

walk(data, None)
for bd, hints in results:
    print('panel bounds:', bd, 'inputs:', hints)
