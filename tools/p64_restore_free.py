#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P64 helper: 把浏览器窗口恢复为自由窗口(点最大化按钮还原),供窗口化模式起跑。"""
import json
import re
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
BUNDLE = 'com.browseros.kaihong'


def sh(cmd, tmo=40):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True,
                       timeout=tmo, errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump():
    sh('uitest dumpLayout -p /data/local/tmp/p64r.json', 50)
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p64r.json',
                    'p64r_layout.json'], capture_output=True, text=True, timeout=30)
    with open('p64r_layout.json', encoding='utf-8', errors='replace') as f:
        return f.read()


def walk(n):
    if isinstance(n, dict):
        a = n.get('attributes')
        if isinstance(a, dict):
            yield a
        for c in (n.get('children') or []):
            yield from walk(c)
    elif isinstance(n, list):
        for c in n:
            yield from walk(c)


sh('aa start -a EntryAbility -b ' + BUNDLE)
time.sleep(3)
lay = dump()
if 'com.browseros.kaihong' not in lay:
    sh('aa start -a EntryAbility -b ' + BUNDLE)
    time.sleep(3)
    lay = dump()
# 最大化按钮仍显示 maximize 图标 → 当前是最大化状态,点击还原为自由窗口
mb = None
for a in walk(json.loads(lay)):
    if a.get('id') == 'EnhanceMaximizeBtn':
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', str(a.get('bounds', '')))
        if m:
            mb = tuple(map(int, m.groups()))
print('EnhanceMaximizeBtn:', mb)
if mb:
    sh('uitest uiInput click %d %d' % ((mb[0] + mb[2]) // 2, (mb[1] + mb[3]) // 2))
    time.sleep(2)
    lay2 = dump()
    # 还原后窗口变小;确认 Toolbar 按钮 y 带仍在
    print('after restore: BrowserOS in dump =', 'com.browseros.kaihong' in lay2)
else:
    print('already free-window (no MaximizeBtn meaning maximize state?)')
