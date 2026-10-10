#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P20-C: BrowserOS (KaihongOS VM) 冒烟回归脚本
用法: python tools/smoke_reg.py [--hdc HDC_PATH] [--target 127.0.0.1:15566] [--hap xxx.hap]

检查链 (绿色=PASS / 红色=FAIL, 退出码 0=全绿 / 1=有红):
  1. hdc 目标在线 (tconn + list targets)
  2. bundle 已安装 (bm dump -n com.browseros.kaihong)
  3. 冷启动 (force-stop → aa start → hilog 出现 EntryAbility onCreate)
  4. 前台渲染 (uitest dumpLayout 含 BrowserOS 标题/地址栏)
  5. 无障碍标注落地 (源码静态计数 accessibilityText ≥ 20)
  6. MCP HTTP 服务 (fport 9222 → POST initialize 带 token)
  7. 书签页搜索框 (点全部书签入口 → dump 含 搜索书签 placeholder)
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

BUNDLE = 'com.browseros.kaihong'
ABILITY = 'EntryAbility'
SRC = os.path.join(os.path.dirname(__file__), '..', 'entry', 'src', 'main', 'ets')
HTTP_PORT = 9222
WS_PORT = 8765

PASS, FAIL, SKIP = '\x1b[32mPASS\x1b[0m', '\x1b[31mFAIL\x1b[0m', '\x1b[33mSKIP\x1b[0m'
results = []


def run(cmd, timeout=30, shell=False):
    try:
        r = subprocess.run(cmd, capture_output=True, encoding='utf-8', timeout=timeout,
                           shell=shell, errors='replace')
        return r.returncode, (r.stdout or '') + (r.stderr or '')
    except Exception as e:
        return 1, str(e)


def record(name, ok, detail=''):
    results.append((name, ok, detail))
    print(('[%s] %s%s' % (PASS if ok else FAIL, name, (' — ' + detail) if detail else '')))


class Hdc:
    def __init__(self, hdc, target):
        self.hdc = hdc
        self.target = target

    def sh(self, cmd, timeout=30):
        if self.target:
            c = '%s -t %s shell %s' % (self.hdc, self.target, cmd)
        else:
            c = '%s shell %s' % (self.hdc, cmd)
        return run(c, timeout=timeout)

    def raw(self, args, timeout=60):
        return run('%s %s' % (self.hdc, args), timeout=timeout)


def check_device(hdc):
    code, out = hdc.raw('list targets' if not hdc.target else 'list targets')
    ok = hdc.target in out if hdc.target else ('[Empty]' not in out and len(out.strip()) > 0)
    record('1.device online', ok, out.strip().splitlines()[0] if out.strip() else 'no target')
    return ok


def check_installed(hdc):
    code, out = hdc.sh('bm dump -n %s' % BUNDLE, 20)
    ok = BUNDLE in out and 'not' not in out.lower()[:60]
    record('2.bundle installed', ok, BUNDLE if ok else out.strip()[:80])


def check_launch(hdc):
    hdc.sh('hilog -r')
    hdc.sh('aa force-stop %s' % BUNDLE)
    time.sleep(1)
    code, out = hdc.sh('aa start -a %s -b %s' % (ABILITY, BUNDLE))
    started = 'successfully' in out
    time.sleep(4)
    code2, logs = hdc.sh('"hilog -x | grep -E \'EntryAbility (onCreate|onForeground)\' | tail -4"', 25)
    ok = started and ('onCreate' in logs or 'onForeground' in logs)
    record('3.cold launch', ok, ('lifecycle OK' if ok else out.strip()[:60] + ' | logs:' + logs.strip()[:60]))


def check_render(hdc):
    hdc.sh('uitest dumpLayout -p /data/local/tmp/smoke_reg.json', 40)
    hdc.raw('file recv /data/local/tmp/smoke_reg.json smoke_reg_layout.json', 30)
    try:
        with open('smoke_reg_layout.json', encoding='utf-8') as f:
            lay = f.read()
        ok = 'BrowserOS' in lay and 'TextInput' in lay
        record('4.foreground render', ok, 'title+omnibox found' if ok else 'layout missing markers')
        return lay
    except Exception as e:
        record('4.foreground render', False, str(e)[:80])
        return ''


def check_a11y_static():
    total = 0
    for root, _, files in os.walk(SRC):
        for fn in files:
            if fn.endswith('.ets'):
                try:
                    with open(os.path.join(root, fn), encoding='utf-8') as f:
                        total += f.read().count('accessibilityText')
                except Exception:
                    pass
    record('5.a11y annotations(static)', total >= 20, 'accessibilityText x%d (>=20)' % total)


def check_mcp_http(hdc):
    code, out = hdc.sh('cat /data/app/el2/100/base/%s/haps/entry/files/mcp_token.txt' % BUNDLE, 15)
    token = out.strip().splitlines()[-1].strip() if out.strip() else ''
    if not token:
        record('6.MCP HTTP initialize', False, 'no token file')
        return
    hdc.raw('fport tcp:%d tcp:%d' % (HTTP_PORT, HTTP_PORT), 20)
    body = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
                       'params': {'protocolVersion': '2024-11-05', 'capabilities': {},
                                  'clientInfo': {'name': 'smoke_reg', 'version': '1.0'}}}).encode()
    req = urllib.request.Request(
        'http://127.0.0.1:%d/mcp?token=%s' % (HTTP_PORT, token), data=body,
        headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode())
            ok = 'result' in data and 'serverInfo' in str(data.get('result', {}))
            record('6.MCP HTTP initialize', ok, str(data)[:80])
    except Exception as e:
        record('6.MCP HTTP initialize', False, str(e)[:80])


def check_bm_search(hdc, lay):
    # 从布局找 全部书签 入口 bounds
    m = re.search(r'"text":"全部书签[^"]*","bounds":"(\[[\d,\]\[]+\])"', lay) or \
        re.search(r'全部书签[^<]{0,80}?(\[\d+,\d+\]\[\d+,\d+\])', lay)
    if not m:
        record('7.bookmarks search box', False, '入口未找到(可能非新标签页)')
        return
    b = m.group(1)
    xs = [int(v) for v in re.findall(r'\d+', b)]
    cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
    hdc.sh('"uinput -T -c %d %d"' % (cx, cy), 20)
    time.sleep(2)
    hdc.sh('uitest dumpLayout -p /data/local/tmp/smoke_bm.json', 40)
    hdc.raw('file recv /data/local/tmp/smoke_bm.json smoke_bm_layout.json', 30)
    try:
        with open('smoke_bm_layout.json', encoding='utf-8') as f:
            p = f.read()
        ok = '搜索书签' in p
        record('7.bookmarks search box', ok, 'placeholder 搜索书签 ' + ('found' if ok else 'MISSING'))
    except Exception as e:
        record('7.bookmarks search box', False, str(e)[:80])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--hdc', default=r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe')
    ap.add_argument('--target', default='127.0.0.1:15566')
    ap.add_argument('--skip-install', action='store_true')
    args = ap.parse_args()

    hdc = Hdc(args.hdc, args.target)
    print('== BrowserOS smoke regression ==')
    print('hdc:', args.hdc, ' target:', args.target)

    if not check_device(hdc):
        _summary()
        return 1
    check_installed(hdc)
    check_launch(hdc)
    lay = check_render(hdc)
    check_a11y_static()
    check_mcp_http(hdc)
    check_bm_search(hdc, lay)
    return _summary()


def _summary():
    reds = [r for r in results if not r[1]]
    print('--')
    print('TOTAL %d  PASS %d  FAIL %d' % (len(results), len(results) - len(reds), len(reds)))
    for n, ok, d in reds:
        print('  FAIL:', n, '—', d)
    return 1 if reds else 0


if __name__ == '__main__':
    sys.exit(main())
