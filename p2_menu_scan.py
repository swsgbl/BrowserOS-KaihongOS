# -*- coding: utf-8 -*-
"""找编辑菜单（全选/剪切）按钮 bounds"""
import io, re, json

raw = io.open(r'D:\BrowserOS - KaihongOS\p2_menu.json', encoding='utf-8').read()
for kw in ('全选', '剪切', '选择全部', 'Select All', 'Cut'):
    i = raw.find(kw)
    if i >= 0:
        pre = raw[max(0, i-700):i]
        j = pre.rfind('"bounds"')
        print(kw, '->', pre[j:j+40] if j >= 0 else 'no-bounds')
    else:
        print(kw, '-> NOT FOUND')
