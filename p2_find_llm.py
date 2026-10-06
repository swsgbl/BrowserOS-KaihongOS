# -*- coding: utf-8 -*-
"""找 LLM 设置行 + 设置面板元素坐标（用最新 layout）"""
import json, io, re, sys

src = sys.argv[1] if len(sys.argv) > 1 else r'D:\BrowserOS - KaihongOS\p2_layout.json'
with io.open(src, encoding='utf-8') as f:
    data = json.load(f)

out = []

def walk(node):
    a = node.get('attributes', {}) or {}
    t = str(a.get('text', ''))
    hint = str(a.get('hint', ''))
    bd = str(a.get('bounds', ''))
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', bd)
    if m:
        x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
        cx, cy = (x1+x2)//2, (y1+y2)//2
        if ('LLM' in t or '保存' in t or 'API' in hint or 'Key' in hint or '模型' in hint or '端点' in hint
              or '已配置' in t or '未配置' in t):
            out.append((t[:36] or hint[:36], cx, cy))
    for c in (node.get('children') or []):
        walk(c)

walk(data)
for o in out:
    print(o)
