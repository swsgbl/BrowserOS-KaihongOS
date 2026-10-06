# -*- coding: utf-8 -*-
"""P2 完整流程：LLM 配置 → 保存 → 创建代理 → 跑任务"""
import subprocess, time

TARGET = '127.0.0.1:15566'

def sh(cmd):
    r = subprocess.run(['hdc', '-t', TARGET, 'shell', cmd], capture_output=True, text=True, timeout=30)
    print((cmd[:70] + '..') if len(cmd) > 70 else cmd, '->', (r.stdout or r.stderr).strip()[:50])
    return r

def tap(x, y):
    sh(f'uitest uiInput click {x} {y}')

def activate():
    sh('uitest uiInput keyEvent 2016')

def type_text(x, y, text):
    tap(x, y)
    activate()
    sh(f"uitest uiInput inputText {x} {y} '{text}'")

# 1) LLM 设置三字段
type_text(800, 319, 'http://10.0.2.2:11434/v1')
time.sleep(0.4)
type_text(800, 394, 'qwen38:latest')
time.sleep(0.4)
tap(800, 434)  # 保存
time.sleep(1.5)

# 2) 代理表单
type_text(800, 514, 't2')
time.sleep(0.3)
type_text(800, 551, 'https://example.com')
time.sleep(0.3)
type_text(800, 589, 'title')
time.sleep(0.3)
tap(800, 630)  # 创建代理
time.sleep(2)
print('=== DONE, check hilog ===')
