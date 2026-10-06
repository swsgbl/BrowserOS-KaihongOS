# -*- coding: utf-8 -*-
"""重填表单（值已清空）+ 创建，观察 LLM 请求结果"""
import subprocess, time

TARGET = '127.0.0.1:15566'

def sh(cmd, wait=0.3):
    subprocess.run(['hdc', '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=30)
    time.sleep(wait)

def tap(x, y):
    sh(f'uitest uiInput click {x} {y}')

def activate():
    sh('uitest uiInput keyEvent 2016')

def type_text(x, y, text):
    tap(x, y)
    activate()
    sh(f"uitest uiInput inputText {x} {y} '{text}'", 0.4)

type_text(800, 514, 't3')
type_text(800, 551, 'https://example.com')
type_text(800, 589, 'open page tell title')
tap(800, 630)
print('form filled + create clicked')
