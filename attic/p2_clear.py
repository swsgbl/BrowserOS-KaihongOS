# -*- coding: utf-8 -*-
"""清空端点输入框（longPress→全选→剪切）+ 输入新端点 + 保存 + 重建代理"""
import subprocess, time

TARGET = '127.0.0.1:15566'

def sh(cmd, wait=0.4):
    r = subprocess.run(['hdc', '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=30)
    time.sleep(wait)
    return r

def tap(x, y):
    sh(f'uitest uiInput click {x} {y}')

def type_text(x, y, text):
    tap(x, y)
    sh('uitest uiInput keyEvent 2016')
    sh(f"uitest uiInput inputText {x} {y} '{text}'", 0.5)

# 1) 清空端点框 (800,319)：longPress 800ms → 全选(2019?) → 剪切
sh('uitest uiInput longPress 800 319 800', 0.6)
# 菜单出现后：全选 = keyEvent 2019? 用 dump 找菜单项坐标更稳，但先试标准键码
# ArkTS 全选菜单常见坐标：菜单在 longPress 点下方
sh('uitest dumpLayout -p /data/local/tmp/p2_menu.json', 0.5)
subprocess.run(['hdc', '-t', TARGET, 'file', 'recv', '/data/local/tmp/p2_menu.json',
                r'D:\BrowserOS - KaihongOS\p2_menu.json'], capture_output=True, text=True)
print('menu dumped')
