# -*- coding: utf-8 -*-
"""segment dump：LLM 接入 之后的 3000 字符原样打印（含转义看格式）"""
import io

raw = io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8').read()
i = raw.find('LLM')
print('idx', i)
print(raw[i:i+3000])
