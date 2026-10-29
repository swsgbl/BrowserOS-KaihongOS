#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P64 probe: dump layout in current window mode, print top-area nodes (buttons/images)
to find structural invariant for the ⋮ menu button across window modes."""
import json
import re
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
BUNDLE = 'com.browseros.kaihong'
MODE = sys.argv[1] if len(sys.argv) > 1 else 'as-is'  # as-is | maximize


def sh(cmd, tmo=40):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True,
                       timeout=tmo, errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()


def dump(tag):
    sh('uitest dumpLayout -p /data/local/tmp/p64_%s.json' % tag, 50)
    r = subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p64_%s.json' % tag,
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


def main():
    # cold launch for clean state
    sh('aa force-stop %s' % BUNDLE)
    time.sleep(1)
    sh('aa start -a EntryAbility -b %s' % BUNDLE)
    time.sleep(6)
    lay = dump('m1')
    data = json.loads(lay)
    print('=== MODE: %s (as-launched) ===' % MODE)
    print('--- all nodes with y1<600, x1>800 (top-right area) ---')
    rows = []
    for a, node in walk(data):
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if y1 < 600 and x1 > 800:
            rows.append((y1, x1, a.get('type'), a.get('id') or '', (a.get('text') or '')[:16], b))
    rows.sort()
    for y1, x1, tp, nid, txt, b in rows:
        print('%4d %5d %-10s %-22s %-16s %s' % (y1, x1, tp, nid, txt, b))
    print()
    print('--- all Button nodes anywhere (sorted by y,x) ---')
    rows = []
    for a, node in walk(data):
        if a.get('type') != 'Button':
            continue
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        rows.append((y1, x1, a.get('id') or '', (a.get('text') or '')[:12], b))
    rows.sort()
    for y1, x1, nid, txt, b in rows:
        print('%4d %5d %-24s %-12s %s' % (y1, x1, nid, txt, b))
    print()
    print('--- all Image nodes y1<200 (toolbar strip) ---')
    rows = []
    for a, node in walk(data):
        if a.get('type') != 'Image':
            continue
        b = str(a.get('bounds', ''))
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if y1 < 200:
            rows.append((y1, x1, a.get('id') or '', b))
    rows.sort()
    for y1, x1, nid, b in rows:
        print('%4d %5d %-26s %s' % (y1, x1, nid, b))
    # window-mode markers
    print()
    ids = set()
    for a, _ in walk(data):
        if a.get('id'):
            ids.add(a['id'])
    print('Enhance ids present:', sorted(i for i in ids if 'Enhance' in i))
    print('key attr sample (first attr dict with extra keys):')
    for a, _ in walk(data):
        extra = {k: a[k] for k in a if k not in
                 ('type', 'text', 'id', 'bounds', 'accessible', 'checked', 'index')}
        if extra:
            print(' ', json.dumps(extra, ensure_ascii=False)[:300])
            break


if __name__ == '__main__':
    main()
