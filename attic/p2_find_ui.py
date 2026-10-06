# -*- coding: utf-8 -*-
"""dump p2_layout.json: find key UI nodes with bounds."""
import json, re, io, sys

PATH = r'D:\BrowserOS - KaihongOS\p2_layout.json'
KEYS = sys.argv[1].split('|') if len(sys.argv) > 1 else ['代理', 'LLM', '创建']

with io.open(PATH, encoding='utf-8') as f:
    data = json.load(f)

results = []

def walk(node):
    a = node.get('attributes', {}) if isinstance(node, dict) else {}
    text = str(a.get('text', ''))
    aid = str(a.get('id', ''))
    s = text + ' ' + aid
    if any(k in s for k in KEYS):
        bd = str(a.get('bounds', ''))
        m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', bd)
        if m:
            x1, y1, x2, y2 = (int(m.group(i)) for i in (1, 2, 3, 4))
            results.append((s.strip()[:60], (x1 + x2) // 2, (y1 + y2) // 2))
    for c in (node.get('children') or []):
        walk(c)

walk(data)
for r in results:
    print(r)
