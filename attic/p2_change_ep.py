# -*- coding: utf-8 -*-
"""菜单可能已消失。换方案：直接向 TextInput inputText 覆盖——实测 inputText 是替换语义（第一次输入空框）。
但框已有值时会 append？P1 记忆说 append-only。稳妥方案：backspace 逐个删（26 字符）。
keyEvent 2055 = backspace。先点框聚焦，再连按 backspace。"""
import subprocess, time

TARGET = '127.0.0.1:15566'

def sh(cmd, wait=0.15):
    subprocess.run(['hdc', '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=30)
    time.sleep(wait)

sh('uitest uiInput click 800 319', 0.4)
sh('uitest uiInput keyEvent 2016', 0.3)
# 连按 30 次 backspace 清空（值 26 字符 + 裕量）
for _ in range(30):
    sh('uitest uiInput keyEvent 2055', 0.05)
# 输入新端点
sh("uitest uiInput inputText 800 319 'http://172.25.0.1:11434/v1'", 0.5)
# 保存
sh('uitest uiInput click 800 434', 1.2)
print('endpoint changed + saved')
