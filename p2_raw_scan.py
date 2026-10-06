# -*- coding: utf-8 -*-
"""直接打印 JSON 里 hint 字段出现处上下文 + 所有 text 属性非空节点"""
import json, io

with io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8') as f:
    raw = f.read()

# 1) hint 出现次数
import re
hints = re.findall(r'"hint":\s*"([^"]{1,60})"', raw)
print('hints found:', hints[:10])

# 2) text 非空
texts = re.findall(r'"text":\s*"([^"]{1,60})"', raw)
print('texts:', [t for t in texts if t][:30])

# 3) TextInput 类型
tis = re.findall(r'"type":\s*"(TextInput[^"]*)"', raw)
print('TextInput types:', tis[:10])
