#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P64 probe2: maximize window, dump again, compare toolbar strip; also scan
non-empty description/a11y fields across both dumps."""
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


def dump(tag):
    sh('uitest dumpLayout -p /data/local/tmp/p64_%s.json' % tag, 50)
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p64_%s.json' % tag,
                    'p64_%s_layout.json' % tag], capture_output=True, text=True, timeout=30)
    with open('p64_%s_layout.json' % tag, encoding='utf-8', errors='replace') as f:
        return f.read()


def walk(node):
    if isinstance(node, dict):
        attrs = node.get('attributes')
        if isinstance(attrs, dict):
            yield attrs, node
        for ch in (node.get('children') or []):
            yield from walk(ch)
    elif isinstance(node, list):
        for ch in node:
            yield from walk(ch)


def bparse(b):
    m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', str(b))
    return tuple(map(int, m.groups())) if m else None


def report(lay, label):
    data = json.loads(lay)
    print('=== %s ===' % label)
    rows = []
    for a, node in walk(data):
        m = bparse(a.get('bounds', ''))
        if not m:
            continue
        x1, y1, x2, y2 = m
        if a.get('type') == 'Button' and y1 < 250 and x1 > 900 and 'Enhance' not in str(a.get('id', '')):
            rows.append((y1, x1, (x2 - x1), (y2 - y1), a.get('id') or ''))
    rows.sort()
    for y1, x1, w, h, nid in rows:
        print('  Button y1=%d x1=%d %dx%d id=%r' % (y1, x1, w, h, nid))
    ids = set()
    for a, _ in walk(data):
        if a.get('id'):
            ids.add(a['id'])
    print('  Enhance present:', sorted(i for i in ids if 'Enhance' in i) or 'NONE(maximized)')
    # non-empty a11y-ish fields
    hits = {}
    for a, _ in walk(data):
        for k in ('description', 'accessibilityId', 'text'):
            v = (a.get(k) or '').strip()
            if v and k != 'text':
                hits.setdefault(k, []).append(v)
    for k, vs in hits.items():
        print('  %s non-empty: %s' % (k, vs[:10]))
    return data


def main():
    lay_free = dump('free0')
    # click maximize
    data = json.loads(lay_free)
    mb = None
    for a, _ in walk(data):
        if a.get('id') == 'EnhanceMaximizeBtn':
            m = bparse(a.get('bounds', ''))
            if m:
                mb = m
    if mb:
        cx, cy = (mb[0] + mb[2]) // 2, (mb[1] + mb[3]) // 2
        sh('uitest uiInput click %d %d' % (cx, cy))
        time.sleep(2)
        print('clicked maximize at', cx, cy)
    else:
        print('already maximized (no EnhanceMaximizeBtn)')
    lay_max = dump('max0')
    report(lay_free, 'FREE-WINDOW mode')
    report(lay_max, 'MAXIMIZED mode')
    # save both for reference
    with open('p64_free_layout.json', 'w', encoding='utf-8') as f:
        f.write(lay_free)
    with open('p64_max_layout.json', 'w', encoding='utf-8') as f:
        f.write(lay_max)


if __name__ == '__main__':
    main()
