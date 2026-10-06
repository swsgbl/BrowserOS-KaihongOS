# -*- coding: utf-8 -*-
import io

raw = io.open(r'D:\BrowserOS - KaihongOS\p2_fresh.json', encoding='utf-8').read()
for kw in ('代理名称', '目标URL', 'LLM 设置', '已配置', '未配置'):
    i = raw.find(kw)
    print('===', kw, 'idx', i)
    if i >= 0:
        pre = raw[max(0, i-700):i]
        j = pre.rfind('"bounds"')
        print('   bounds:', pre[j:j+40] if j >= 0 else 'N/A')
