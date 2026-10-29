#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P20-C: BrowserOS (KaihongOS VM) 冒烟回归脚本
用法: python tools/smoke_reg.py [--hdc HDC_PATH] [--target 192.168.161.137:10178] [--hap xxx.hap]

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
MAXIMIZE = False  # P64: 默认按原样窗口跑(结构化定位不依赖坐标窗口);--maximize 开启
hdc_g = None      # _grab helper 用的全局 Hdc 引用(main 里注入)


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
        if self.target:
            return run('%s -t %s %s' % (self.hdc, self.target, args), timeout=timeout)
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


def _maximize_window(hdc):
    """P49/P64: 仅 --maximize 时先把自由窗口最大化(统一坐标);默认关闭,
    让结构化定位在【原样窗口模式】下接受检验(两种模式都必须 9/9)。"""
    if not MAXIMIZE:
        return
    hdc.sh('uitest dumpLayout -p /data/local/tmp/smoke_mx.json', 40)
    hdc.raw('file recv /data/local/tmp/smoke_mx.json smoke_mx_layout.json', 30)
    try:
        with open('smoke_mx_layout.json', encoding='utf-8') as f:
            lay = f.read()
    except Exception:
        return
    mb = _find_node_id(lay, 'EnhanceMaximizeBtn')
    if mb:
        xs = [int(v) for v in re.findall(r'\d+', mb)]
        hdc.sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2), 20)
        time.sleep(1.2)


def _find_node_id(lay_text, idval):
    try:
        data = json.loads(lay_text)
    except json.JSONDecodeError:
        return None
    for attrs in _walk(data):
        if attrs.get('id') == idval:
            b = str(attrs.get('bounds', ''))
            if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', b):
                return b
    return None


def check_render(hdc):
    _maximize_window(hdc)
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
    # P39: 宿主 9222 可能被本机其它进程占用（fport listen failed→404 假象）——
    # 用宿主侧高位端口 19222 隧道到设备 9222，先清旧映射
    host_port = 19222
    hdc.raw('fport rm tcp:%d tcp:%d' % (host_port, HTTP_PORT), 15)
    hdc.raw('fport tcp:%d tcp:%d' % (host_port, HTTP_PORT), 20)
    body = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
                       'params': {'protocolVersion': '2024-11-05', 'capabilities': {},
                                  'clientInfo': {'name': 'smoke_reg', 'version': '1.0'}}}).encode()
    req = urllib.request.Request(
        'http://127.0.0.1:%d/mcp?token=%s' % (host_port, token), data=body,
        headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode())
            ok = 'result' in data and 'serverInfo' in str(data.get('result', {}))
            record('6.MCP HTTP initialize', ok, str(data)[:80])
    except Exception as e:
        record('6.MCP HTTP initialize', False, str(e)[:80])


def _walk(node):
    if isinstance(node, dict):
        attrs = node.get('attributes')
        if isinstance(attrs, dict):
            yield attrs
        for ch in (node.get('children') or []):
            yield from _walk(ch)
    elif isinstance(node, list):
        for ch in node:
            yield from _walk(ch)


def _find_node(lay_text, needle, exact=False):
    """JSON-tree lookup: node whose own text matches, return its bounds."""
    try:
        data = json.loads(lay_text)
    except json.JSONDecodeError:
        return None
    for attrs in _walk(data):
        t = attrs.get('text') or ''
        if (exact and t == needle) or (not exact and needle in t):
            b = str(attrs.get('bounds', ''))
            if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', b):
                return b
    return None


def _find_menu_btn(lay_text):
    """P64 结构化定位 ⋮ 菜单钮(窗口化/最大化两模式通吃的结构不变量):
    以顶部宽地址栏(TextInput 类,y 带为锚)为参照,取同一 y 带、位于地址栏右侧、
    尺寸<=64px 的图标 Button 中最右者。Enhance*(系统窗控)按 id 排除。
    返回 bounds 元组 (x1,y1,x2,y2) 或 None。"""
    try:
        data = json.loads(lay_text)
    except json.JSONDecodeError:
        return None
    nodes = list(_walk(data))
    # 1) 锚: 宽>=300 的顶部地址输入框(两种模式下工具栏都含它)
    anchor = None
    for a in nodes:
        if a.get('type') not in ('TextInput', 'TextField', 'SearchField'):
            continue
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', str(a.get('bounds', '')))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if (x2 - x1) >= 300 and y1 < 300:
            if anchor is None or y1 < anchor[1]:
                anchor = (x1, y1, x2, y2)
    if not anchor:
        return None
    band_top, band_bot = anchor[1] - 8, anchor[3] + 8
    # 2) 同 y 带、地址栏右侧的小图标 Button,取最右
    best = None
    for a in nodes:
        if a.get('type') != 'Button' or 'Enhance' in str(a.get('id', '')):
            continue
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', str(a.get('bounds', '')))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        cy = (y1 + y2) // 2
        if not (band_top <= cy <= band_bot):
            continue
        if x1 < anchor[2] or x1 < 600:   # 必须在地址栏右侧
            continue
        if (x2 - x1) > 64 or (y2 - y1) > 64:  # 图标钮尺寸门
            continue
        if best is None or x2 > best[2]:
            best = (x1, y1, x2, y2)
    return best


def _grab(tag):
    """dump+recv+read 一步到位(P64 抽取的公共helper)。"""
    hdc_g.sh('uitest dumpLayout -p /data/local/tmp/%s.json' % tag, 40)
    hdc_g.raw('file recv /data/local/tmp/%s.json %s_layout.json' % (tag, tag), 30)
    try:
        with open('%s_layout.json' % tag, encoding='utf-8', errors='replace') as f:
            return f.read()
    except Exception:
        return ''


def check_bm_search(hdc, lay):
    # P64 焦点防御:VM 多窗口下 dump 可能抓到别的 app(如终端)——校验归属,不对就拉回重抓
    if 'com.browseros.kaihong' not in lay:
        hdc.sh('aa start -a %s -b %s' % (ABILITY, BUNDLE))
        time.sleep(3)
    # P33 起启动 +5s 可能弹「更新内容」覆盖层——现抓新 dump,先关掉它再点菜单
    hdc.sh('uitest dumpLayout -p /data/local/tmp/smoke_s7.json', 40)
    hdc.raw('file recv /data/local/tmp/smoke_s7.json smoke_s7_layout.json', 30)
    try:
        with open('smoke_s7_layout.json', encoding='utf-8', errors='replace') as f:
            lay = f.read()
    except Exception:
        pass
    if 'com.browseros.kaihong' not in lay:  # P64: 重抓后仍非目标窗口→拉前台再抓一次
        print('  [warn] s7 dump not browseros; markers:',
              [s for s in re.findall(r'"bundleName":"([^"]+)"', lay)][:3])
        hdc.sh('aa start -a %s -b %s' % (ABILITY, BUNDLE))
        time.sleep(3)
        lay = _grab('smoke_s7')
    ob = _find_node(lay, '知道了', exact=True)
    if ob:
        xs = [int(v) for v in re.findall(r'\d+', ob)]
        hdc.sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2), 20)
        time.sleep(1.5)
        hdc.sh('uitest dumpLayout -p /data/local/tmp/smoke_s7.json', 40)
        hdc.raw('file recv /data/local/tmp/smoke_s7.json smoke_s7_layout.json', 30)
        try:
            with open('smoke_s7_layout.json', encoding='utf-8', errors='replace') as f:
                lay = f.read()
        except Exception:
            pass
    # P64: ⋮ 菜单结构化定位(替代坐标窗口过滤——窗口化模式 y1=43 被旧 y1>=60 条件误杀)
    mb = _find_menu_btn(lay)
    if not mb:
        record('7.bookmarks search box', False, '⋮ 菜单按钮未找到(结构化定位失败)')
        return
    cx, cy = (mb[0] + mb[2]) // 2, (mb[1] + mb[3]) // 2
    hdc.sh('uitest uiInput click %d %d' % (cx, cy), 20)
    time.sleep(2.5)
    menu = _grab('smoke_menu')
    if not _find_node(menu, '书签', exact=True):
        # P64: 完整重试点链(菜单未开→拉前台+重新结构定位再点,首击可能被动画/焦点吞)
        hdc.sh('aa start -a %s -b %s' % (ABILITY, BUNDLE))
        time.sleep(1.5)
        lay2 = _grab('smoke_s7')
        if 'com.browseros.kaihong' in lay2:
            mb2 = _find_menu_btn(lay2)
            if mb2:
                cx, cy = (mb2[0] + mb2[2]) // 2, (mb2[1] + mb2[3]) // 2
        hdc.sh('uitest uiInput click %d %d' % (cx, cy), 20)
        time.sleep(2.0)
        menu = _grab('smoke_menu')
    if not _find_node(menu, '书签', exact=True):
        # P64 诊断:菜单仍未开——打印 dump 归属与文本样本,供矩阵 FAIL 细节引用
        import re as _re
        marks = _re.findall(r'"bundleName":"([^"]+)"', menu)[:3]
        texts = [t for t in _re.findall(r'"text":"([^"]{1,14})"', menu)][:12]
        print('  [diag] menu-not-open windows=%s texts=%s' % (marks, texts))
    ib = _find_node(menu, '书签', exact=True)
    if not ib:
        record('7.bookmarks search box', False, '菜单项 书签 未找到')
        return
    xs = [int(v) for v in re.findall(r'\d+', ib)]
    hdc.sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2), 20)
    time.sleep(2)
    hdc.sh('uitest dumpLayout -p /data/local/tmp/smoke_bm.json', 40)
    hdc.raw('file recv /data/local/tmp/smoke_bm.json smoke_bm_layout.json', 30)
    try:
        with open('smoke_bm_layout.json', encoding='utf-8', errors='replace') as f:
            p = f.read()
        ok = '搜索书签' in p
        record('7.bookmarks search box', ok, 'placeholder 搜索书签 ' + ('found' if ok else 'MISSING'))
    except Exception as e:
        record('7.bookmarks search box', False, str(e)[:80])


def check_new_pages(hdc):
    """8. P34/P35 新屏注册与入口：main_pages 13 页 + ⋮ 菜单含 Skills 项（复用第 7 步菜单 dump）"""
    ok_pages = True
    detail = ''
    try:
        with open(os.path.join(SRC, '..', 'resources', 'base', 'profile', 'main_pages.json'),
                  encoding='utf-8') as f:
            prof = f.read()
        need = ['SkillsPage', 'JtbdSurveyPage', 'UltrafastWaitlistPage']
        missing = [n for n in need if n not in prof]
        ok_pages = not missing
        detail = 'main_pages ok' if ok_pages else 'missing: ' + ','.join(missing)
    except Exception as e:
        ok_pages = False
        detail = str(e)[:60]
    menu_ok = False
    try:
        with open('smoke_menu_layout.json', encoding='utf-8', errors='replace') as f:
            menu = f.read().replace('”', '"')
        # P49-A: 菜单项已 i18n（zh=技能 / en=Skills）
        menu_ok = '"技能"' in menu or '"Skills"' in menu
    except Exception:
        menu_ok = False
    record('8.p34/p35 screens registered', ok_pages and menu_ok,
           detail + ('; menu Skills found' if menu_ok else '; menu Skills MISSING'))


def check_icon_render(hdc):
    """9. 图标渲染像素门禁（P37 教训固化）：同启动 dump 定位标签条小 Image -> 截图 -> 该区域非背景像素 >= 15%
    （防资源 id 错位导致的全应用图标空白回退）"""
    try:
        from PIL import Image
    except ImportError:
        record('9.icon pixel gate', False, 'PIL not installed')
        return
    hdc.sh('uitest dumpLayout -p /data/local/tmp/smoke_ic.json', 40)
    hdc.raw('file recv /data/local/tmp/smoke_ic.json smoke_ic_layout.json', 30)
    try:
        with open('smoke_ic_layout.json', encoding='utf-8', errors='replace') as f:
            lay = f.read()
    except Exception as e:
        record('9.icon pixel gate', False, str(e)[:60])
        return
    img_b = None
    try:
        data = json.loads(lay)
        for a in _walk(data):
            if a.get('type') != 'Image':
                continue
            b = str(a.get('bounds', ''))
            m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
            if not m:
                continue
            x1, y1, x2, y2 = map(int, m.groups())
            # 标签条区：屏幕左 1/4、非顶部窗口栏、小尺寸(<=30px)、窗口内
            if x2 <= 450 and 120 < y1 and (y2 - y1) <= 30 and (x2 - x1) >= 8:
                img_b = (x1, y1, x2, y2)
                break
    except Exception:
        pass
    if not img_b:
        record('9.icon pixel gate', False, 'strip Image node not found')
        return
    hdc.sh('snapshot_display -f /data/local/tmp/smoke_ic.jpeg', 40)
    hdc.raw('file recv /data/local/tmp/smoke_ic.jpeg smoke_ic_shot.jpeg', 30)
    try:
        im = Image.open('smoke_ic_shot.jpeg').convert('L').crop(img_b)
        px = list(im.getdata())
        total = len(px)
        bg = max(set(px), key=px.count)
        nonbg = sum(1 for v in px if abs(v - bg) > 25)
        pct = 100.0 * nonbg / total if total else 0
        if pct >= 15.0:
            record('9.icon pixel gate', True, 'icon %s non-bg %.1f%% (>=15)' % (img_b, pct))
        else:
            # P40: root cause FIXED - build_api23_hap.py now emits an all-STORED zip
            # (KaihongOS resmgr cannot read DEFLATED hap entries; that blanked every
            # in-app icon). Icon blanks are a real regression again - hard fail, no SKIP.
            record('9.icon pixel gate', False, 'icon %s non-bg %.1f%% (<15)' % (img_b, pct))
    except Exception as e:
        record('9.icon pixel gate', False, str(e)[:60])


def main():
    global hdc_g
    ap = argparse.ArgumentParser()
    ap.add_argument('--hdc', default=r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe')
    ap.add_argument('--target', default='192.168.161.137:10178')
    ap.add_argument('--skip-install', action='store_true')
    ap.add_argument('--maximize', action='store_true',
                    help='P64: 启动后先最大化窗口统一坐标(默认关,验证结构化定位)')
    global MAXIMIZE
    args = ap.parse_args()
    MAXIMIZE = args.maximize

    hdc = Hdc(args.hdc, args.target)
    hdc_g = hdc
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
    check_new_pages(hdc)
    check_icon_render(hdc)
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
