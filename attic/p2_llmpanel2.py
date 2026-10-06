# -*- coding: utf-8 -*-
"""LLM 面板容器：找 text='LLM 接入' 的祖先 Column，dump 它整棵子树"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

chain = []

def find(node, cur):
    a = node.get('attributes', {}) or {}
    if str(a.get('text', '')) == 'LLM 接入（OpenAI 兼容）':
        return cur + [node]
    for c in (node.get('children') or []):
        r = find(c, cur + [node])
        if r:
            return r
    return None

p = find(data, [])
# 面板容器是'LLM 接入'的父 Column（p[-2]）
panel = p[-2] if len(p) >= 2 else None

def dump(n, d):
    aa = n.get('attributes', {}) or {}
    bd = parse(aa.get('bounds', ''))
    c = f"({(bd[0]+bd[2])//2},{(bd[1]+bd[3])//2})" if bd else ''
    print('  '*d, aa.get('type', '?'), '|', str(aa.get('text', ''))[:26], '|', str(aa.get('hint', ''))[:36], '|', c)
    for ch in (n.get('children') or []):
        dump(ch, d+1)

if panel is not None:
    dump(panel, 0)
