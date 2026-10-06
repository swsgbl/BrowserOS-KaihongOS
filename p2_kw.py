# -*- coding: utf-8 -*-
"""直接看 p2_fresh.json 里有没有'保存'与'模型名'原文，打印上下文 500 字符。"""
import io

raw = io.open(r'D:\BrowserOS - KaihongOS\p2_fresh.json', encoding='utf-8').read()
for kw in ('保存', '模型名', '创建代理', '任务描述'):
    i = raw.find(kw)
    print('===', kw, 'idx', i)
    if i >= 0:
        # 向前找最近的 bounds
        pre = raw[max(0, i-700):i]
        j = pre.rfind('"bounds"')
        print('   nearest-bounds-before:', pre[j:j+40] if j >= 0 else 'N/A')
