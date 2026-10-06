# -*- coding: utf-8 -*-
"""从 API-TextInput 向下无法拿 bounds；改从'保存'Button 定位。
全文档找 text=保存 的 Button bounds。"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

def walk(node):
    a = node.get('attributes', {}) or {}
    t = str(a.get('text', ''))
    ty = str(a.get('type', ''))
    bd = parse(a.get('bounds', ''))
    if t == '保存' and bd:
        print('保存 Button:', bd, 'center=', ((bd[0]+bd[2])//2, (bd[1]+bd[3])//2))
    # 同时找'创建代理'按钮（新布局下的）
    if t == '创建代理' and bd:
        print('创建代理 Button:', bd, 'center=', ((bd[0]+bd[2])//2, (bd[1]+bd[3])//2))
    if '任务描述' == str(a.get('hint', '')):
        pass
    for c in (node.get('children') or []):
        walk(c)

walk(data)
