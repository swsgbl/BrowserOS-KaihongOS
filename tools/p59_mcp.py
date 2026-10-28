#!/usr/bin/env python3
"""P59 tooling base: MCP client helpers for live-page inspection (WPS menu etc)."""
import json
import subprocess
import sys
import time
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
HOST_PORT = 9222
_id = [0]


def sh(cmd, tmo=60):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def fport_up():
    subprocess.run([HDC, '-t', T, 'fport', 'rm', 'tcp:%d' % HOST_PORT, 'tcp:9222'], capture_output=True)
    subprocess.run([HDC, '-t', T, 'fport', 'tcp:%d' % HOST_PORT, 'tcp:9222'], capture_output=True)
    time.sleep(1)


def get_token():
    out = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt')
    return out.strip().splitlines()[-1]


def rpc(method, params):
    _id[0] += 1
    return {'jsonrpc': '2.0', 'id': _id[0], 'method': method, 'params': params}


def post(qs, body, timeout=60):
    import time as _t
    last = None
    for i in range(6):
        try:
            req = urllib.request.Request('http://127.0.0.1:%d%s' % (HOST_PORT, qs),
                                         data=json.dumps(body).encode(),
                                         headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, json.loads(resp.read().decode()), dict(resp.headers)
        except OSError as e:
            last = e
            _t.sleep(1.2 + i)
    raise last


def session(qs):
    code, init, hdrs = post(qs, rpc('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'p59-inspect', 'version': '1.0.0'}
    }))
    assert code == 200, init
    return hdrs.get('Mcp-Session-Id', '')


def call_tool(qs, sid, name, args, timeout=90):
    code, r, _ = post(qs, rpc('tools/call', {'name': name, 'arguments': args}),
                      timeout=timeout, headers={'Mcp-Session-Id': sid} if sid else None) if False else post_with_sid(qs, rpc('tools/call', {'name': name, 'arguments': args}), sid, timeout)
    return r


def post_with_sid(qs, body, sid, timeout=60):
    h = {'Content-Type': 'application/json'}
    if sid:
        h['Mcp-Session-Id'] = sid
    import time as _t
    last = None
    for i in range(6):
        try:
            req = urllib.request.Request('http://127.0.0.1:%d%s' % (HOST_PORT, qs),
                                         data=json.dumps(body).encode(), headers=h)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, json.loads(resp.read().decode()), dict(resp.headers)
        except OSError as e:
            last = e
            _t.sleep(1.2 + i)
    raise last


def result_text(r):
    """extract text content from tools/call result"""
    try:
        content = r['result']['content']
        return '\n'.join(c.get('text', '') for c in content)
    except Exception:
        return json.dumps(r, ensure_ascii=False)[:2000]
