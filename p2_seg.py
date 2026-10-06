# -*- coding: utf-8 -*-
"""从'LLM 接入'原文位置向后取 4000 字符，抽取所有 type/text/hint/bounds 对"""
import io, re

raw = io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8').read()
i = raw.find('LLM 接入')
seg = raw[i:i+4000]
pairs = re.findall(r'"(type|text|hint|bounds)": "([^"]{0,60})"', seg)
for k, v in pairs:
    print(k, '=', v)
