# -*- coding: utf-8 -*-
"""新代理：t4 / example.com / 任务，创建后观察"""
import subprocess, time

TARGET = '127.0.0.1:15566'

def sh(cmd, wait=0.3):
    subprocess.run(['hdc', '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=30)
    time.sleep(wait)

def tap(x, y):
    sh(f'uitest uiInput click {x} {y}')

def type_text(x, y, text):
    tap(x, y)
    sh('uitest uiInput keyEvent 2016')
    sh(f"uitest uiInput inputText {x} {y} '{text}'", 0.4)

type_text(800, 514, 't4')
type_text(800, 551, 'https://example.com')
type_text(800, 589, 'open and tell title')
tap(800, 630)
print('t4 created')
