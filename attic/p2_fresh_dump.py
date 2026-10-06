# -*- coding: utf-8 -*-
"""结构没问题——那可能是这个 p2_layout.json 是旧 dump（无设置面板展开）。
先重新 dump 当前屏，再全量提取。"""
import json, io, re, subprocess, sys

# 1) fresh dump
subprocess.run(['hdc', '-t', '127.0.0.1:15566', 'shell', 'uitest dumpLayout -p /data/local/tmp/p2_fresh.json'],
               capture_output=True, text=True)
subprocess.run(['hdc', '-t', '127.0.0.1:15566', 'file', 'recv', '/data/local/tmp/p2_fresh.json',
                r'D:\BrowserOS - KaihongOS\p2_fresh.json'], capture_output=True, text=True)

with io.open(r'D:\BrowserOS - KaihongOS\p2_fresh.json', encoding='utf-8') as f:
    data = json.load(f)

def parse(s):
    m = re.search(r'\[\[(\d+),(\d+)\]\[(\d+),(\d+)\]\]', str(s))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) if m else None

def walk(node):
    a = node.get('attributes') or {}
    hint = str(a.get('hint', ''))
    t = str(a.get('text', ''))
    bd = parse(a.get('bounds', ''))
    if bd and (hint or t):
        c = ((bd[0]+bd[2])//2, (bd[1]+bd[3])//2)
        print(f"{c} | {t[:30] or ''} | {hint[:40]}")
    for ch in (node.get('children') or []):
        walk(ch)

walk(data)
