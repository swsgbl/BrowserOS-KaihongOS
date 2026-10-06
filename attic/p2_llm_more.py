# -*- coding: utf-8 -*-
"""从 raw JSON 提取：模型名 TextInput + 保存 Button bounds"""
import io, re

raw = io.open(r'D:\BrowserOS - KaihongOS\p2_layout.json', encoding='utf-8').read()
i = raw.find('模型名')
seg = raw[i:i+1200]
# TextInput bounds 是它前面的（attributes 里 bounds 先于 hint 出现）
m = re.findall(r'"bounds": "(\[\d+,\d+\]\[\d+,\d+\])"[^}]*?"hint": "模型名', raw)
print('模型名 TextInput bounds:', m)
m2 = re.findall(r'"bounds": "(\[\d+,\d+\]\[\d+,\d+\])"[^}]*?"text": "保存"', raw)
print('保存 Button bounds:', m2)
m3 = re.findall(r'"bounds": "(\[\d+,\d+\]\[\d+,\d+\])"[^}]*?"text": "创建代理"', raw)
print('创建代理 bounds:', m3)
