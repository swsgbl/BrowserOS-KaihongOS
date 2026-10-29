#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P64 debug: regression_20 上下文里菜单链失败根因——模拟同样序列(force-stop→start→render→s7 dump→点⋮)"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding='utf-8')
import smoke_reg as sr

sr.MAXIMIZE = False
hdc = sr.Hdc(r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
             '192.168.161.137:10178')
sr.hdc_g = hdc

sr.results.clear()
hdc.sh('aa force-stop %s' % sr.BUNDLE)
time.sleep(1)
ok = sr.check_launch(hdc)
print('launch:', ok)
lay = sr.check_render(hdc)
print('render lay bundle-ok:', 'com.browseros.kaihong' in (lay or ''))
mb = sr._find_menu_btn(lay or '')
print('menu btn on render-dump:', mb)
# s7 dump(模拟 smoke 步骤)
lay2 = sr._grab('dbg_s7')
print('s7 dump bundle-ok:', 'com.browseros.kaihong' in lay2)
mb2 = sr._find_menu_btn(lay2)
print('menu btn on s7-dump:', mb2)
# 覆盖层
ob = sr._find_node(lay2, '知道了', exact=True)
print('overlay 知道了:', ob)
if mb2:
    cx, cy = (mb2[0] + mb2[2]) // 2, (mb2[1] + mb2[3]) // 2
    hdc.sh('uitest uiInput click %d %d' % (cx, cy), 20)
    time.sleep(2.5)
    menu = sr._grab('dbg_menu')
    print('menu dump bundle-ok:', 'com.browseros.kaihong' in menu)
    for w in ('书签', '设置', '技能', '历史'):
        print('  menu has %r:' % w, sr._find_node(menu, w, exact=True) is not None)
    import re
    marks = re.findall(r'"bundleName":"([^"]+)"', menu)[:3]
    print('  menu dump windows:', marks)
    print('  menu text sample:', [t for t in re.findall(r'"text":"([^"]{1,14})"', menu)][:20])
