# -*- coding: utf-8 -*-
"""打印应用主 Column 的直接子结构（找 LLM 设置行的真实 bounds）"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def walk(node):
    a = node.get('attributes', {}) or {}
    t = str(a.get('text', ''))
    if t == 'LLM 设置':
        # 打印它的父链中最近的带 bounds 节点
        return ('found', node)
    for c in (node.get('children') or []):
        r = walk(c)
        if r:
            return r
    return None

# 先找节点路径
path = []

def find_path(node, target_text, cur):
    a = node.get('attributes', {}) or {}
    if str(a.get('text', '')) == target_text:
        return cur + [node]
    for c in (node.get('children') or []):
        r = find_path(c, target_text, cur + [node])
        if r:
            return r
    return None

p = find_path(data, 'LLM 设置', [])
if p:
    for i, n in enumerate(p):
        a = n.get('attributes', {})
        print(i, a.get('type', '?'), '|', a.get('text', '')[:30], '|', a.get('bounds', ''), '| click=', a.get('clickable', ''))
