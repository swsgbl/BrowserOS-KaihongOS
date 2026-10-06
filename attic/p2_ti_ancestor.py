# -*- coding: utf-8 -*-
"""暴力：找全部 hint 含 API 的 TextInput 祖先链 bounds（一层层向上）"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

def find(node, cur):
    a = node.get('attributes', {}) or {}
    hint = str(a.get('hint', ''))
    if 'API' in hint or '模型名' in hint or 'Key' in hint:
        return cur + [node]
    for c in (node.get('children') or []):
        r = find(c, cur + [node])
        if r:
            return r
    return None

p = find(data, [])
if p:
    ti = p[-1]
    hint = ti.get('attributes', {}).get('hint', '')
    print('TextInput:', hint[:40])
    # 祖先中最近带 bounds 的（排除全屏）
    for anc in reversed(p[:-1]):
        bd = parse(anc.get('attributes', {}).get('bounds', ''))
        if bd and bd != (0, 0, 1600, 900) and (bd[2]-bd[0]) < 1200:
            print('nearest bounded ancestor:', anc.get('attributes', {}).get('type'), bd)
            # TextInput 通常占父全宽、高36。若祖先是 Column 高度=多输入框，需要更近层
            break
    # 也打印所有祖先类型+bounds
    for anc in p[:-1][-4:]:
        aa = anc.get('attributes', {})
        print('  anc:', aa.get('type', '?'), aa.get('bounds', ''))
