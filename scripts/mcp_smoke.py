#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
P3 MCP HTTP 传输层冒烟测试（宿主侧，装机阶段由 Zodex 执行）。

用法:
    python scripts/mcp_smoke.py [--host 127.0.0.1] [--port 9222] [--token <auth_token>]

前置:
    1. 应用已装机且 EntryAbility 已拉起（hilog 应有 "MCP-HTTP listening on 0.0.0.0:<port>"）
    2. token 需从设备 hilog 获取 —— P3 当前 token 每次启动随机生成且未外发。
       负向用例（错误 token 断言 401）可先行；正向用例需 token 外显补齐后执行。
    3. 端口转发: qemu/kaihongos VM 需将 guest <port> 转发到宿主（hostfwd 或 hdc fwd）。

校验项:
    [1] initialize       -> 200 + JSON-RPC result + Mcp-Session-Id 响应头
    [2] tools/list       -> 200 + tools 数组含 navigate 等 10 工具
    [3] tools/call(navigate) -> 200 + result.content[0].text 存在
    [4] GET /mcp         -> 405
    [5] 错误 token       -> 401
    [6] 未知路径         -> 404
退出码: 0 全过 / 1 有失败
"""
import argparse
import json
import sys
import urllib.request
import urllib.error

PASS, FAIL = [], []


def check(name: str, cond: bool, detail: str = '') -> None:
    (PASS if cond else FAIL).append(name)
    print(f"  [{'PASS' if cond else 'FAIL'}] {name}" + (f"  -- {detail}" if detail and not cond else ''))


def http_raw(host, port, method='POST', path='/mcp', body=None, timeout=15):
    """返回 (status, headers, body_text)"""
    url = f"http://{host}:{port}{path}"
    data = body.encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, dict(resp.headers), resp.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read().decode('utf-8', 'replace')


def rpc_call(host, port, token, method, params=None, rpc_id=1):
    body = {'jsonrpc': '2.0', 'id': rpc_id, 'method': method}
    if params is not None:
        body['params'] = params
    path = f"/mcp?token={token}"
    return http_raw(host, port, 'POST', path, json.dumps(body))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, default=9222)
    ap.add_argument('--token', default='')
    args = ap.parse_args()
    host, port, token = args.host, args.port, args.token

    print(f"== MCP smoke against http://{host}:{port} token_len={len(token)} ==")

    # [4] GET /mcp -> 405
    st, hd, _ = http_raw(host, port, 'GET', '/mcp')
    check('GET /mcp returns 405', st == 405, f'status={st}')

    # [6] unknown path -> 404
    st, hd, _ = http_raw(host, port, 'POST', '/nope')
    check('POST /nope returns 404', st == 404, f'status={st}')

    # [5] no/wrong token -> 401
    st, hd, body = rpc_call(host, port, 'WRONGTOKEN', 'tools/list')
    check('wrong token returns 401', st == 401, f'status={st} body={body[:120]}')

    if not token:
        print('\n!! --token 未提供：跳过鉴权后用例（initialize/tools/list/tools/call）。')
        print('   token 获取途径见脚本头部注释。')
        summary()
        return

    # [1] initialize
    st, hd, body = rpc_call(host, port, token, 'initialize',
                            {'protocolVersion': '2024-11-05',
                             'capabilities': {},
                             'clientInfo': {'name': 'smoke', 'version': '0.1'}}, rpc_id=1)
    ok_struct = False
    session_id = ''
    try:
        j = json.loads(body)
        ok_struct = j.get('jsonrpc') == '2.0' and j.get('id') == 1 and 'result' in j
        session_id = (hd.get('Mcp-Session-Id') or hd.get('mcp-session-id') or '')
    except Exception:
        pass
    check('initialize: 200 + JSON-RPC result', st == 200 and ok_struct, f'status={st} body={body[:200]}')
    check('initialize: Mcp-Session-Id header present', bool(session_id), f'headers={list(hd.keys())}')
    print(f'     session id = {session_id}')

    # [2] tools/list
    st, hd, body = rpc_call(host, port, token, 'tools/list', {}, rpc_id=2)
    names = []
    try:
        j = json.loads(body)
        names = [t.get('name') for t in j.get('result', {}).get('tools', [])]
    except Exception:
        pass
    check('tools/list: 200 + tools array', st == 200 and len(names) > 0, f'status={st} body={body[:200]}')
    print(f'     tools = {names}')
    check('tools/list: navigate present', 'navigate' in names)

    # [3] tools/call navigate
    st, hd, body = rpc_call(host, port, token, 'tools/call',
                            {'name': 'navigate',
                             'arguments': {'url': 'https://example.com'}}, rpc_id=3)
    ok = False
    try:
        j = json.loads(body)
        r = j.get('result', {})
        ok = isinstance(r.get('content'), list) and len(r['content']) > 0 and 'text' in r['content'][0]
        if j.get('error'):
            ok = False
            body += f"  (rpc error: {j['error']})"
    except Exception:
        pass
    check('tools/call navigate: 200 + result.content[0].text', st == 200 and ok, f'status={st} body={body[:300]}')

    summary()


def summary():
    print(f"\n== RESULT: {len(PASS)} passed, {len(FAIL)} failed ==")
    if FAIL:
        print('failed: ' + ', '.join(FAIL))
        sys.exit(1)
    sys.exit(0)


if __name__ == '__main__':
    main()
