# -*- coding: utf-8 -*-
"""regex 顺序问题：hint 在 bounds 前面。调整：找含'模型名'的 attributes 块"""
import io, re

raw = io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8').read()

# attributes 块内 hint 与 bounds 顺序不定，用非贪婪跨属性匹配整个 {..}
for pat, name in [
    (r'"hint": "模型名[^"]*"[^}]*?"bounds": "(\[[\d,]+\]\[[\d,]+\])"', '模型名(hint先)'),
    (r'"bounds": "(\[[\d,]+\]\[[\d,]+\])"[^}]*?"hint": "模型名[^"]*"', '模型名(bounds先)'),
    (r'"text": "保存"[^}]*?"bounds": "(\[[\d,]+\]\[[\d,]+\])"', '保存(text先)'),
    (r'"bounds": "(\[[\d,]+\]\[[\d,]+\])"[^}]*?"text": "保存"', '保存(bounds先)'),
    (r'"text": "创建代理"[^}]*?"bounds": "(\[[\d,]+\]\[[\d,]+\])"', '创建代理(text先)'),
    (r'"bounds": "(\[[\d,]+\]\[[\d,]+\])"[^}]*?"text": "创建代理"', '创建代理(bounds先)'),
]:
    m = re.findall(pat, raw)
    if m:
        print(name, '->', m)
