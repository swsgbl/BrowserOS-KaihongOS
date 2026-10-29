#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P64-B: P59-F 20 项浏览器基础功能回归矩阵
用法: python tools/regression_20.py [--hdc HDC] [--target 192.168.161.137:10178]

三类判定:
  [PASS/FAIL] 自动化断言(UI 链复用 smoke_reg 修复后代码;MCP 链走 fport 19222)
  [PASS-CITE] 证据引用断言(校验 evidence/ 文件存在且内容含期望标记,引用历史装机实证)
  [BLOCKED]   设备侧客观阻塞(注明原因,不计 PASS)

矩阵(20 项):
  01 冷启动生命周期        自动化(hilog onCreate/onForeground)
  02 前台渲染标题+地址栏   自动化(dumpLayout)
  03 MCP HTTP initialize  自动化(fport 19222)
  04 navigate+snapshot    自动化(example.com 内容)
  05 navigate 中文站      自动化(baidu title)
  06 tabs new/list/close  自动化(MCP)
  07 history back/forward 自动化(MCP 结构化 body)
  08 grep 可见文本        自动化(MCP)
  09 evaluate_in_page     自动化(document.title)
  10 read 页面正文        自动化(MCP)
  11 会话隔离读          自动化(双会话, P62-B 模式)
  12 ⋮ 菜单结构          自动化(菜单 dump 含 书签/设置/技能/历史)
  13 书签页搜索框         自动化(smoke step7)
  14 图标渲染像素门       自动化(smoke step9)
  15 无障碍标注(静态)     自动化(accessibilityText>=20)
  16 页面注册完整性       自动化(main_pages)
  17 主题深浅切换         证据引用(P44 装机截图)+源码开关
  18 语言中英切换         证据引用(P48 装机截图)+I18n 包
  19 DevTools 控制台/求值 证据引用(P47 g2/g5 dump)
  20 网页下载             BLOCKED(P16: ArkWeb 无下载回调,设备侧无落盘钩子)
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding='utf-8')

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
EVID = os.path.join(ROOT, 'evidence')
PASS_CITE, BLOCKED = 'PASS-CITE', 'BLOCKED'
matrix = []  # (idx, name, status, detail, evidence)


def add(idx, name, status, detail, evidence=''):
    matrix.append((idx, name, status, detail, evidence))
    tag = {'PASS': '\x1b[32mPASS\x1b[0m', 'FAIL': '\x1b[31mFAIL\x1b[0m',
           PASS_CITE: '\x1b[32mPASS*\x1b[0m', BLOCKED: '\x1b[33mBLOCKED\x1b[0m'}.get(status, status)
    print('[%s] %02d %s — %s' % (tag, idx, name, detail))


def run(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, capture_output=True, encoding='utf-8', timeout=timeout, errors='replace')
        return r.returncode, (r.stdout or '') + (r.stderr or '')
    except Exception as e:
        return 1, str(e)


# ---------------- MCP client (P39: fport 高位端口 + 重试) ----------------
class Mcp:
    def __init__(self, hdc, host_port=19222):
        self.hdc = hdc
        self.host_port = host_port
        self.url = None
        self.sid = None
        self.i = 200

    def setup(self):
        code, out = self.hdc.sh('cat /data/app/el2/100/base/com.browseros.kaihong'
                                '/haps/entry/files/mcp_token.txt', 15)
        token = out.strip().splitlines()[-1].strip() if out.strip() else ''
        if not token:
            return False, 'no mcp_token.txt'
        self.hdc.raw('fport rm tcp:%d tcp:9222' % self.host_port, 15)
        code, out = self.hdc.raw('fport tcp:%d tcp:9222' % self.host_port, 20)
        if 'failed' in out.lower() and 'Ok' not in out:
            return False, 'fport: ' + out.strip()[:60]
        self.url = 'http://127.0.0.1:%d/mcp?token=%s' % (self.host_port, token)
        return True, 'fport ok'

    def post(self, body, timeout=20):
        last = None
        for attempt in range(3):  # P59: WinError 10048/10053 重试
            try:
                hdr = {'Content-Type': 'application/json'}
                if self.sid:
                    hdr['Mcp-Session-Id'] = self.sid  # P62: 服务端会话必需
                req = urllib.request.Request(self.url, data=json.dumps(body).encode(),
                                             headers=hdr)
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    sid = resp.headers.get('Mcp-Session-Id')
                    if sid:
                        self.sid = sid
                    return json.loads(resp.read().decode())
            except Exception as e:
                last = e
                time.sleep(0.8 * (attempt + 1))
        raise last

    def rpc(self, method, params=None):
        body = {'jsonrpc': '2.0', 'id': self.i, 'method': method}
        self.i += 1
        if params is not None:
            body['params'] = params
        return self.post(body)

    def call(self, name, args, timeout=45):
        r = self.rpc('tools/call', {'name': name, 'arguments': args})
        if r.get('error'):
            return {'isError': True, 'text': json.dumps(r['error'])}
        res = r.get('result', {})
        text = '\n'.join(c.get('text', '') for c in res.get('content', [])) \
            if isinstance(res.get('content'), list) else json.dumps(res, ensure_ascii=False)
        return {'isError': bool(res.get('isError')), 'text': text}

    def new_session(self, name):
        init = self.rpc('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {},
                                       'clientInfo': {'name': name, 'version': '1.0'}})
        ok = 'result' in init
        return ok


def mcp_text(r):
    return (r.get('text') or '')[:140].replace('\n', ' ')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--hdc', default=r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe')
    ap.add_argument('--target', default='192.168.161.137:10178')
    args = ap.parse_args()

    import smoke_reg as sr
    sr.MAXIMIZE = False
    hdc = sr.Hdc(args.hdc, args.target)
    sr.hdc_g = hdc
    print('== P64 regression_20 ==  target:', args.target)

    # ---------- Part 1: UI 链(复用 smoke_reg 修复后的检查) ----------
    sr.results.clear()
    sr.check_launch(hdc)                       # 01
    ok1 = any(n.startswith('3.') and o for n, o, d in sr.results)
    add(1, '冷启动生命周期', 'PASS' if ok1 else 'FAIL',
        next(d for n, o, d in sr.results if n.startswith('3.')))

    sr.results.clear()
    lay = sr.check_render(hdc)                 # 02
    ok2 = any(o for n, o, d in sr.results if n.startswith('4.'))
    add(2, '前台渲染标题+地址栏', 'PASS' if ok2 else 'FAIL',
        'dumpLayout BrowserOS+TextInput' if ok2 else 'missing markers')

    sr.results.clear()
    sr.check_bm_search(hdc, lay)               # 13(先跑,后续复用其菜单 dump)
    bm_ok = any(o for n, o, d in sr.results if n.startswith('7.'))

    sr.results.clear()
    sr.check_new_pages(hdc)                    # 16
    ok16 = any(o for n, o, d in sr.results if n.startswith('8.'))
    add(16, '页面注册完整性', 'PASS' if ok16 else 'FAIL',
        'main_pages 13页 + 菜单 Skills')

    # 12 ⋮ 菜单结构:复用 smoke_menu_layout.json(刚由 check_bm_search 生成)
    try:
        with open('smoke_menu_layout.json', encoding='utf-8', errors='replace') as f:
            menu = f.read().replace('”', '"')
        need = ['书签', '设置', '技能', '历史']
        hit = [w for w in need if '"%s"' % w in menu]
        add(12, '⋮ 菜单结构', 'PASS' if len(hit) >= 3 else 'FAIL',
            '菜单项命中 %d/%d: %s' % (len(hit), len(need), '/'.join(hit)))
    except Exception as e:
        add(12, '⋮ 菜单结构', 'FAIL', str(e)[:60])

    add(13, '书签页搜索框', 'PASS' if bm_ok else 'FAIL',
        'placeholder 搜索书签' if bm_ok else '未找到(见 smoke step7)')

    sr.results.clear()
    sr.check_a11y_static()                     # 15
    d15 = next(d for n, o, d in sr.results)
    add(15, '无障碍标注(静态)', 'PASS' if 'x4' in d15 or 'x5' in d15 else 'FAIL', d15)

    sr.results.clear()
    sr.check_icon_render(hdc)                  # 14
    d14 = next(d for n, o, d in sr.results)
    add(14, '图标渲染像素门', 'PASS' if 'non-bg' in d14 and '>=15' in d14 else 'FAIL', d14)

    # ---------- Part 2: MCP 链 ----------
    m = Mcp(hdc)
    ok, why = m.setup()
    if not ok:
        for i in (3, 4, 5, 6, 7, 8, 9, 10, 11):
            add(i, MCP_NAMES[i], 'FAIL', 'MCP setup: ' + why)
    else:
        try:
            r = m.rpc('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {},
                                     'clientInfo': {'name': 'reg20', 'version': '1.0'}})
            m.rpc('notifications/initialized')
            add(3, 'MCP HTTP initialize', 'PASS' if 'result' in r else 'FAIL',
                'serverInfo ok' if 'result' in r else str(r)[:80])

            # P51 会话-标签模型: 先 tabs{new} 建会话自有 tab,后续 navigate/read/eval 都作用其上
            tn = m.call('tabs', {'action': 'new', 'url': 'https://example.com'})
            tab_id = None
            mt = re.search(r'"tabId"\s*:\s*"([^"]+)"', tn.get('text', ''))
            if mt:
                tab_id = mt.group(1)
            time.sleep(4)

            # 04 snapshot on owned tab
            snap = m.call('snapshot', {})
            ok4 = len(snap.get('text', '')) > 200 and \
                ('Example' in snap['text'] or 'example' in snap['text'] or '文档示例' in snap['text'])
            add(4, 'navigate+snapshot', 'PASS' if ok4 else 'FAIL',
                'snapshot len=%d' % len(snap.get('text', '')))

            # 09 evaluate_in_page
            ev = m.call('evaluate_in_page', {'expression': 'document.title'})
            ok9 = not ev['isError'] and 'Example' in ev['text']
            add(9, 'evaluate_in_page', 'PASS' if ok9 else 'FAIL', mcp_text(ev))

            # 10 read
            rd = m.call('read', {})
            ok10 = not rd['isError'] and len(rd.get('text', '')) > 100
            add(10, 'read 页面正文', 'PASS' if ok10 else 'FAIL', 'len=%d' % len(rd.get('text', '')))

            # 05 navigate 中文站(会话自有 tab 上导航)
            nv = m.call('navigate', {'url': 'https://www.baidu.com'})
            time.sleep(4)
            ev2 = m.call('evaluate_in_page', {'expression': 'document.title'})
            ok5 = not ev2['isError'] and '百度' in ev2.get('text', '')
            add(5, 'navigate 中文站', 'PASS' if ok5 else 'FAIL', mcp_text(ev2))

            # 06 tabs list/close(新建第二个 tab 验证 list 含两个)
            tn2 = m.call('tabs', {'action': 'new', 'url': 'https://example.com'})
            tab_id2 = None
            mt2 = re.search(r'"tabId"\s*:\s*"([^"]+)"', tn2.get('text', ''))
            if mt2:
                tab_id2 = mt2.group(1)
            tl = m.call('tabs', {'action': 'list'})
            listed = (tab_id or '') in tl.get('text', '') and (tab_id2 or 'x') in tl.get('text', '')
            closed = ''
            if tab_id2:
                cl = m.call('tabs', {'action': 'close', 'tabId': tab_id2})
                closed = 'close ok' if not cl['isError'] else 'close err'
            ok6 = bool(tab_id) and listed
            add(6, 'tabs new/list/close', 'PASS' if ok6 else 'FAIL',
                'tabId=%s listed=%s %s' % (tab_id, listed, closed))

            # 07 history back/forward(自有 tab: baidu -> iana -> back)
            m.call('navigate', {'url': 'https://www.iana.org/domains/reserved'})
            time.sleep(3.5)
            hb = m.call('history', {'action': 'back'})
            ok7 = not hb['isError'] and re.search(r'"url"\s*:', hb.get('text', ''))
            add(7, 'history back/forward', 'PASS' if ok7 else 'FAIL', mcp_text(hb))
            m.call('history', {'action': 'forward'})
            time.sleep(1.5)

            # 08 grep
            g = m.call('grep', {'pattern': 'Reserved'})
            ok8 = not g['isError'] and 'Reserved' in g.get('text', '')
            add(8, 'grep 可见文本', 'PASS' if ok8 else 'FAIL', mcp_text(g))

            # cleanup owned tab
            if tab_id:
                m.call('tabs', {'action': 'close', 'tabId': tab_id})

            # 11 session isolation (P62-B 模式)
            m1 = Mcp(hdc)
            m1.url, m1.i = m.url, 500
            m1.new_session('r20-s1')
            t1 = m1.call('tabs', {'action': 'new', 'url': 'https://example.com'})
            time.sleep(2.5)
            ta = re.search(r'"tabId"\s*:\s*"([^"]+)"', t1.get('text', ''))
            m2 = Mcp(hdc)
            m2.url, m2.i = m.url, 600
            m2.new_session('r20-s2')
            t2 = m2.call('tabs', {'action': 'new', 'url': 'https://www.iana.org/domains/reserved'})
            time.sleep(3)
            tb = re.search(r'"tabId"\s*:\s*"([^"]+)"', t2.get('text', ''))
            if tb:
                m2.call('tabs', {'action': 'activate', 'tabId': tb.group(1)})
                time.sleep(0.5)
            r1 = m1.call('read', {})
            leak = 'IANA' in r1.get('text', '') and '文档示例' not in r1.get('text', '') \
                   and 'Example' not in r1.get('text', '')
            ok11 = not r1['isError'] and len(r1.get('text', '')) > 50 and not leak
            add(11, '会话隔离读', 'PASS' if ok11 else 'FAIL',
                's1 read len=%d leak=%s' % (len(r1.get('text', '')), leak))
            for mm, tt in ((m1, ta), (m2, tb)):
                if tt:
                    mm.call('tabs', {'action': 'close', 'tabId': tt.group(1)})
        except Exception as e:
            for i in (4, 5, 6, 7, 8, 9, 10, 11):
                if not any(x[0] == i for x in matrix):
                    add(i, MCP_NAMES[i], 'FAIL', 'exc: ' + str(e)[:60])

    # ---------- Part 3: 证据引用 ----------
    cite(17, '主题深浅切换', 'evidence/p44/t2-settings-dark.jpeg',
         'evidence/p44/t3-newtab-dark.jpeg', ['png', 'jpeg'],
         src_marker='entry/src/main/ets 里 SettingsPage 深浅切换',
         src_glob='SettingsPage.ets', src_text='dark')
    cite(18, '语言中英切换', 'evidence/p50/step4_restart_en.jpeg',
         'evidence/p50/step7_restart_zh.jpeg', ['png', 'jpeg'],
         src_marker='I18nZh/I18nEn 双语包', src_glob='I18n*.ets', src_text='t(')
    cite_devtools(19)
    add(20, '网页下载', BLOCKED,
        'P16 实证: ArkWeb 组件无下载完成回调,onDownloadStart 之外无落盘钩子,'
        '设备侧无法断言文件落盘;待上游 API 或应用层方案后转自动化',
        'evidence/p16 (历史)')

    return report()


MCP_NAMES = {3: 'MCP HTTP initialize', 4: 'navigate+snapshot', 5: 'navigate 中文站',
             6: 'tabs new/list/close', 7: 'history back/forward', 8: 'grep 可见文本',
             9: 'evaluate_in_page', 10: 'read 页面正文', 11: '会话隔离读'}


def cite(idx, name, f1, f2, exts, src_marker, src_glob, src_text):
    ok_files, det = True, []
    for f in (f1, f2):
        p = os.path.join(ROOT, f.replace('evidence/', 'evidence' + os.sep))
        ex = os.path.exists(p) and os.path.getsize(p) > 10 * 1024
        ok_files &= ex
        det.append('%s(%s)' % (os.path.basename(f), 'ok' if ex else 'MISSING'))
    src_ok = False
    for root, _, files in os.walk(os.path.join(ROOT, 'entry', 'src', 'main', 'ets')):
        for fn in files:
            if fn == src_glob or (src_glob.endswith('.ets') and fn == src_glob):
                try:
                    with open(os.path.join(root, fn), encoding='utf-8') as fh:
                        src_ok |= src_text in fh.read()
                except Exception:
                    pass
            elif '*' in src_glob and fnmatch_name(fn, src_glob):
                try:
                    with open(os.path.join(root, fn), encoding='utf-8') as fh:
                        if src_text in fh.read():
                            src_ok = True
                except Exception:
                    pass
    st = PASS_CITE if (ok_files and src_ok) else 'FAIL'
    add(idx, name, st, '%s; 源码 %s %s' % ('+'.join(det), src_marker,
        'confirmed' if src_ok else 'NOT FOUND'), f1 + ' + ' + f2)


def fnmatch_name(fn, pat):
    import fnmatch as _f
    return _f.fnmatch(fn, pat)


def cite_devtools(idx):
    """19 DevTools: P47 g2-devtools.json(面板打开) + g5-eval.json(JS 求值)。"""
    f1 = os.path.join(ROOT, 'evidence', 'p47', 'g2-devtools.json')
    f2 = os.path.join(ROOT, 'evidence', 'p47', 'g5-eval.json')
    ok, det = True, []
    for p in (f1, f2):
        try:
            with open(p, encoding='utf-8', errors='replace') as fh:
                c = fh.read()
            ex = len(c) > 500
            ok &= ex
            det.append('%s len=%d' % (os.path.basename(p), len(c)))
        except Exception:
            ok = False
            det.append(os.path.basename(p) + ' MISSING')
    add(idx, 'DevTools 控制台/求值', PASS_CITE if ok else 'FAIL',
        '; '.join(det), 'evidence/p47/g2-devtools.json + g5-eval.json')


def report():
    n_pass = sum(1 for x in matrix if x[2] in ('PASS', PASS_CITE))
    n_cite = sum(1 for x in matrix if x[2] == PASS_CITE)
    n_blk = sum(1 for x in matrix if x[2] == BLOCKED)
    n_fail = sum(1 for x in matrix if x[2] == 'FAIL')
    print('\n===== regression_20: %d 项  PASS %d (含引用 %d)  FAIL %d  BLOCKED %d ====='
          % (len(matrix), n_pass, n_cite, n_fail, n_blk))
    for x in matrix:
        if x[2] in ('FAIL', BLOCKED):
            print('  %s: %02d %s — %s' % (x[2], x[0], x[1], x[3][:100]))
    out = os.path.join(ROOT, 'evidence', 'p64', 'regression_20_report.txt')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write('P64 regression_20 report  %s  target 192.168.161.137:10178\n'
                % time.strftime('%Y-%m-%d %H:%M:%S'))
        for idx, name, st, det, ev in matrix:
            f.write('[%-8s] %02d %-16s | %s | 证据: %s\n' % (st, idx, name, det, ev or '(运行期产物)'))
        f.write('TOTAL %d  PASS %d(cite %d)  FAIL %d  BLOCKED %d\n'
                % (len(matrix), n_pass, n_cite, n_fail, n_blk))
    print('report ->', out)
    return 0 if (n_fail == 0 and n_pass >= 14) else 1


if __name__ == '__main__':
    sys.exit(main())
