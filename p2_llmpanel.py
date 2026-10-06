# -*- coding: utf-8 -*-
"""打印 LLM 设置面板的 TextInput/保存按钮 bounds（从'LLM 接入'文本往下找兄弟容器）"""
import json, io, re

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

def walk(node):
    a = node.get('attributes', {}) or {}
    if str(a.get('text', '')) == 'LLM 接入（OpenAI 兼容）':
        return node
    for c in (node.get('children') or []):
        r = walk(c)
        if r:
            return r
    return None

node = walk(data)
if node:
    # 向上找包含容器（面板 Column）
    def find_parent(target, cur):
        for c in (cur.get('children') or []):
            if c is target:
                return cur
            r = find_parent(target, c)
            if r:
                return r
        return None

    def dump(n, d):
        aa = n.get('attributes', {}) or {}
        bd = parse(aa.get('bounds', ''))
        c = ((bd[0]+bd[2])//2, (bd[1]+bd[3])//2) if bd else None
        print('  '*d, aa.get('type', '?'), '|', str(aa.get('text', ''))[:24], '|', str(aa.get('hint', ''))[:34], '|', aa.get('bounds', ''), '| c=', c)
        for ch in (n.get('children') or []):
            dump(ch, d+1)

    # 从'LLM 接入'节点本身往下 dump
    dump(node, 0)
