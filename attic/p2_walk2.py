# -*- coding: utf-8 -*-
"""关键洞察：attributes 是一个 JSON 对象，bounds 和 hint 同级。
用 json 解析后遍历，这次正确检查 attributes dict 的 key。"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

def walk(node):
    a = node.get('attributes', {}) or {}
    hint = str(a.get('hint', ''))
    t = str(a.get('text', ''))
    bd = parse(a.get('bounds', ''))
    if bd:
        c = ((bd[0]+bd[2])//2, (bd[1]+bd[3])//2)
        if '模型名' in hint or t == '保存' or t == '创建代理' or 'API' in hint or 'Key' in hint:
            print(repr(t[:16] or hint[:36]), bd, 'center=', c)
    for ch in (node.get('children') or []):
        walk(ch)

walk(data)
