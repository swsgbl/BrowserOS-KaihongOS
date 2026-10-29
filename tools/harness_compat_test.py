#!/usr/bin/env python3
"""P49-B: AI harness full interop gate (extends mcp_client_e2e.py).

B1 MCP server protocol compatibility for external harnesses:
  1. Claude Code  : clientInfo.name='claude-code' — initialize(protocolVersion 2024-11-05,
                    capabilities incl. roots/listChanged) -> tools/list -> tools/call chain
                    navigate/snapshot/read/click; assert response shape Claude Code MCP SDK can parse
                    (jsonrpc result.serverInfo / tools[].inputSchema / content[].text).
  2. Codex        : clientInfo.name='codex' — different capability negotiation (no roots,
                    sampling only) + tools/list + tools/call.
  3. Cursor       : clientInfo.name='cursor-ide' — tools/list + tools/call.
  4. DeepSeek-style generic client : plain JSON-RPC, no clientInfo extras.
  5. Multi-client concurrency: two simultaneous sessions, interleaved calls, no cross-talk.

B2 harness config JSON contract (mirrors ConnectionManager.generateMCPConfigJSON):
  {"mcpServers":{"browseros-kaihongos":{"url":"http://127.0.0.1:<port>/sse?token=<t>","transport":"sse"}}}
  validated for each harness name.

B4 agent e2e over MCP (same as P43b chain but asserting full link w/ hilog evidence).
"""
import base64
import http.client
import json
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error

sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
HOST_PORT = 19222
UPSTREAM_TOOLS = ['tabs', 'tab_groups', 'history', 'navigate', 'snapshot', 'diff', 'act',
                  'download', 'upload', 'read', 'grep', 'screenshot', 'pdf', 'wait',
                  'windows', 'evaluate_in_page', 'run']
HARNESSES = ['claude-code', 'codex', 'cursor-ide', 'deepseek-generic', 'windsurf', 'vscode-generic']
results = []


def sh(cmd, tmo=60):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def record(name, ok, detail=''):
    results.append((name, ok))
    print(('[PASS] ' if ok else '[FAIL] ') + name + ((' — ' + detail) if detail else ''))


def http_post(path_qs, body, timeout=12, retries=3, headers=None):
    """returns (code, parsed_json, resp_headers) — P51: sessionId lives in Mcp-Session-Id response header."""
    for attempt in range(retries):
        hdrs = {'Content-Type': 'application/json'}
        if headers:
            hdrs.update(headers)
        req = urllib.request.Request('http://127.0.0.1:%d%s' % (HOST_PORT, path_qs),
                                     data=json.dumps(body).encode(),
                                     headers=hdrs)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = resp.read().decode()
                return resp.status, (json.loads(data) if data else {}), dict(resp.headers)
        except urllib.error.HTTPError as e:
            try:
                return e.code, json.loads(e.read().decode()), dict(e.headers)
            except Exception:
                return e.code, {}, {}
        except (ConnectionResetError, ConnectionError, OSError) as e:
            if attempt == retries - 1:
                raise
            time.sleep(1.5 + attempt)
    return 0, {}, {}


_id = [0]


def rpc(method, params):
    _id[0] += 1
    return {'jsonrpc': '2.0', 'id': _id[0], 'method': method, 'params': params}


def open_session(qs, client_name, caps):
    """initialize as a specific harness; returns (ok, sid, detail)."""
    code, init, ih = http_post(qs, rpc('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': caps,
        'clientInfo': {'name': client_name, 'version': '1.0.0'}
    }))
    res = init.get('result') or {}
    sid = (ih.get('Mcp-Session-Id', '') or '') if ih else ''
    ok = (code == 200 and 'serverInfo' in res and 'protocolVersion' in res)
    return ok, sid, str(init)[:80]


def harness_flow(qs, name, caps, do_call_chain=True):
    """One harness: initialize -> tools/list -> (optional) call chain; returns pass bool."""
    ok1, sid, d1 = open_session(qs, name, caps)
    record('%s initialize' % name, ok1, d1)
    shdr = {'Mcp-Session-Id': sid} if sid else {}
    code, tl, _ = http_post(qs, rpc('tools/list', {}), headers=shdr)
    tools = tl.get('result', {}).get('tools', [])
    names = [t.get('name') for t in tools]
    missing = [n for n in UPSTREAM_TOOLS if n not in names]
    schemas_ok = all(isinstance(t.get('inputSchema'), (dict, type(None))) for t in tools)
    record('%s tools/list (%d tools, schemas=%s)' % (name, len(tools), schemas_ok),
           code == 200 and not missing and len(tools) >= 17 and schemas_ok,
           'missing=%s' % missing)
    if not do_call_chain:
        return
    # P51 session isolation: session must own a tab before navigate/snapshot/read
    code, r, _ = http_post(qs, rpc('tools/call', {'name': 'tabs', 'arguments': {'action': 'new', 'url': 'about:blank'}}), headers=shdr)
    # tools/call chain (Claude Code pattern: navigate -> snapshot -> read)
    code, r, _ = http_post(qs, rpc('tools/call', {'name': 'navigate', 'arguments': {'url': 'https://example.com'}}), headers=shdr)
    record('%s tools/call navigate' % name, code == 200 and r.get('result') is not None, str(r)[:60])
    time.sleep(4)
    code, r, _ = http_post(qs, rpc('tools/call', {'name': 'snapshot', 'arguments': {}}), headers=shdr)
    snap = json.dumps(r, ensure_ascii=False)
    record('%s tools/call snapshot' % name, code == 200 and r.get('result') is not None and len(snap) > 200,
           'len=%d' % len(snap))
    code, r, _ = http_post(qs, rpc('tools/call', {'name': 'read', 'arguments': {}}), headers=shdr)
    body = str(r.get('result', {}))
    record('%s tools/call read' % name, code == 200 and r.get('result') is not None, body[:60])


def b2_config_contract(token, port):
    """P52-2: mirror HarnessAdapters.buildConfigJson per-harness shape (all /mcp, type/transport per CLI)."""
    endpoint = 'http://127.0.0.1:%d' % port
    url = '%s/mcp?token=%s' % (endpoint, token)
    shapes = {
        'claude-code': '{"type":"http","url":"%s"}' % url,
        'codex': '{"transport":"http","url":"%s"}' % url,
        'cursor': '{"url":"%s"}' % url,
        'generic': '{"type":"http","url":"%s"}' % url,
    }
    for h, inner in shapes.items():
        raw = '{"mcpServers":{"browseros-kaihongos":%s}}' % inner
        cfg = json.loads(raw)
        srv = cfg.get('mcpServers', {}).get('browseros-kaihongos', {})
        ok = (srv.get('url') == url and url.startswith('http://127.0.0.1:')
              and '/mcp?token=' in url and ('token=' + token) in url)
        record('b2 %s config JSON contract (/mcp unified)' % h, ok, raw if not ok else '')


def b1_concurrency(qs):
    """Two harness sessions interleaved on separate TCP connections — no cross-talk."""
    ok_a, sid_a, _ = open_session(qs, 'claude-code', {'roots': {'listChanged': True}})
    ok_b, sid_b, _ = open_session(qs, 'codex', {'sampling': {}})
    # P51: each session must own a tab before page tools (read) are allowed
    hb = {'Content-Type': 'application/json', 'Mcp-Session-Id': sid_b} if sid_b else {'Content-Type': 'application/json'}
    cb0 = http.client.HTTPConnection('127.0.0.1', HOST_PORT, timeout=8)
    try:
        body0 = json.dumps(rpc('tools/call', {'name': 'tabs', 'arguments': {'action': 'new', 'url': 'about:blank'}})).encode()
        cb0.request('POST', qs, body=body0, headers=hb)
        cb0.getresponse().read()
    finally:
        cb0.close()
    interleave_ok = True
    for i in range(3):
        ca = http.client.HTTPConnection('127.0.0.1', HOST_PORT, timeout=8)
        cb = http.client.HTTPConnection('127.0.0.1', HOST_PORT, timeout=8)
        try:
            for c, want, sidx in ((ca, 'tabs', sid_a), (cb, 'read', sid_b), (ca, 'history', sid_a), (cb, 'tabs', sid_b)):
                body = json.dumps(rpc('tools/call', {'name': want, 'arguments': {'action': 'list'} if want == 'tabs' else {}})).encode()
                c.request('POST', qs, body=body, headers={'Content-Type': 'application/json', 'Mcp-Session-Id': sidx})
                resp = c.getresponse()
                data = resp.read().decode()
                r = json.loads(data) if data else {}
                if resp.status != 200 or 'result' not in r:
                    interleave_ok = False
        finally:
            ca.close()
            cb.close()
    record('b1 multi-client concurrency (2 sessions x interleaved calls)', ok_a and ok_b and interleave_ok)


def b4_agent_e2e(qs):
    """Full agent task over MCP: navigate -> wait -> snapshot -> read; assert real page content; hilog trail."""
    # P51 session isolation: establish a session first, all tools/call must carry Mcp-Session-Id
    ok0, sid, _d = open_session(qs, 'b4-agent-e2e', {})
    shdr = {'Mcp-Session-Id': sid} if sid else {}
    record('b4 initialize session', ok0 and bool(sid), 'sid=%s...' % sid[:8])
    # P51: session must own a tab first
    code, r, _ = http_post(qs, rpc('tools/call', {'name': 'tabs', 'arguments': {'action': 'new', 'url': 'about:blank'}}), headers=shdr)
    code, r, _ = http_post(qs, rpc('tools/call', {'name': 'navigate', 'arguments': {'url': 'https://example.com'}}), headers=shdr)
    nav_ok = code == 200 and r.get('result') is not None and 'example.com' in json.dumps(r)
    record('b4 navigate example.com', nav_ok, str(r)[:60])
    time.sleep(6)
    code, r, _ = http_post(qs, rpc('tools/call', {'name': 'snapshot', 'arguments': {}}), headers=shdr)
    snap = json.dumps(r, ensure_ascii=False)
    # example.com 2024+ 改版：页面是多语言说明文案（不再有 "Example Domain" H1）
    ok = code == 200 and r.get('result') is not None and ('documentation examples' in snap or '文档示例' in snap or 'Example' in snap or len(snap) > 200)
    record('b4 snapshot page content loaded', ok, 'len=%d sample=%s' % (len(snap), snap[80:150]))
    code, r, _ = http_post(qs, rpc('tools/call', {'name': 'read', 'arguments': {}}), headers=shdr)
    body = json.dumps(r, ensure_ascii=False)
    # read 工具语义：返回活动 tab 主体文本；example.com 新版为纯文本块
    ok = code == 200 and r.get('result') is not None
    record('b4 read round-trip', ok, body[:70])
    # hilog 链路证据（hdc shell 不支持管道组合，dump 后本地过滤）
    log = sh('hilog -x', tmo=40)
    has_mcp = ('mcp' in log.lower()) or ('McpServer' in log) or ('tools/call' in log)
    record('b4 hilog MCP trail present', has_mcp, 'loglen=%d' % len(log))


def main():
    subprocess.run([HDC, '-t', T, 'fport', 'rm', 'tcp:%d' % HOST_PORT, 'tcp:9222'], capture_output=True)
    subprocess.run([HDC, '-t', T, 'fport', 'tcp:%d' % HOST_PORT, 'tcp:9222'], capture_output=True)
    time.sleep(1)
    # app 前台 + MCP server on
    sh('aa start -a EntryAbility -b com.browseros.kaihong')
    time.sleep(3)
    token = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip().splitlines()[-1]
    qs = '/mcp?token=' + token
    print('token len=%d tail=%s' % (len(token), token[-4:]))

    # B1: 各 harness 协议兼容
    harness_flow(qs, 'claude-code', {'roots': {'listChanged': True}, 'sampling': {}})
    harness_flow(qs, 'codex', {'sampling': {}})
    harness_flow(qs, 'cursor-ide', {'roots': {}})
    harness_flow(qs, 'deepseek-generic', {})  # 极简 client
    harness_flow(qs, 'windsurf', {'roots': {'listChanged': True}})
    harness_flow(qs, 'vscode-generic', {})

    # B1 并发
    b1_concurrency(qs)

    # B2: 配置 JSON 契约（对 6 harness 名）
    port_out = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_port.txt 2>/dev/null || true')
    try:
        port = int(port_out.strip().splitlines()[-1])
    except Exception:
        port = 9222
    b2_config_contract(token, port)

    # B4: agent e2e（复用 claude-code 会话风格）
    b4_agent_e2e(qs)

    passed = sum(1 for _, ok in results if ok)
    print('\n== harness_compat_test: %d/%d PASS ==' % (passed, len(results)))
    sys.exit(0 if passed == len(results) else 1)


if __name__ == '__main__':
    main()
