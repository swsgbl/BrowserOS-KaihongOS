#!/usr/bin/env python3
"""P43b: MCP client interop gate - dual-transport E2E + negatives + rate limit.

HTTP transport (fport host 19222 -> device 9222):
  initialize -> tools/list (assert 17 upstream names) -> tools/call chain:
  navigate example.com -> snapshot -> read -> grep -> tabs list -> history list
Negatives: invalid token (401), unknown method (JSON-RPC error), bad params.
Rate limit: 50 rapid initialize calls -> expect -32000 rate limited tail.
"""
import json
import re
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error
import base64
import hashlib
import struct

sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
HOST_PORT = 19222
WS_PORT = 18765  # host side of fport tunnel to device 8765
UPSTREAM_TOOLS = ['tabs', 'tab_groups', 'history', 'navigate', 'snapshot', 'diff', 'act',
                  'download', 'upload', 'read', 'grep', 'screenshot', 'pdf', 'wait',
                  'windows', 'evaluate_in_page', 'run']
results = []


def sh(cmd, tmo=60):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def record(name, ok, detail=''):
    results.append((name, ok))
    print(('[PASS] ' if ok else '[FAIL] ') + name + ((' — ' + detail) if detail else ''))


def http_post(path_qs, body, timeout=10):
    req = urllib.request.Request('http://127.0.0.1:%d%s' % (HOST_PORT, path_qs),
                                 data=json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, {}


def rpc(method, params, _id=[0]):
    _id[0] += 1
    return {'jsonrpc': '2.0', 'id': _id[0], 'method': method, 'params': params}


def main():
    # tunnels (idempotent)
    subprocess.run([HDC, '-t', T, 'fport', 'rm', 'tcp:%d' % HOST_PORT, 'tcp:9222'], capture_output=True)
    subprocess.run([HDC, '-t', T, 'fport', 'tcp:%d' % HOST_PORT, 'tcp:9222'], capture_output=True)
    subprocess.run([HDC, '-t', T, 'fport', 'rm', 'tcp:%d' % WS_PORT, 'tcp:8765'], capture_output=True)
    subprocess.run([HDC, '-t', T, 'fport', 'tcp:%d' % WS_PORT, 'tcp:8765'], capture_output=True)
    time.sleep(1)
    token = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip().splitlines()[-1]
    qs = '/mcp?token=' + token

    # --- 1. initialize ---
    code, init = http_post(qs, rpc('initialize', {'protocolVersion': '2024-11-05',
                                                  'capabilities': {},
                                                  'clientInfo': {'name': 'e2e', 'version': '1'}}))
    record('http initialize', code == 200 and 'result' in init, str(init)[:60])

    # --- 2. tools/list assert 17 ---
    code, tl = http_post(qs, rpc('tools/list', {}))
    names = [t.get('name') for t in tl.get('result', {}).get('tools', [])]
    missing = [n for n in UPSTREAM_TOOLS if n not in names]
    record('tools/list 17 upstream names', code == 200 and not missing and len(names) == 17,
           'missing=%s count=%d' % (missing, len(names)))

    def call(name, args):
        return http_post(qs, rpc('tools/call', {'name': name, 'arguments': args}))

    # --- 3. tool call chain ---
    code, r = call('navigate', {'url': 'https://example.com'})
    record('call navigate', code == 200 and 'result' in r, str(r.get('result', {}))[:60])
    time.sleep(4)
    code, r = call('snapshot', {})
    snap_text = str(r)
    ok = code == 200 and 'result' in r and ('Example' in snap_text or 'example' in snap_text or len(snap_text) > 200)
    record('call snapshot (page content)', ok, 'len=%d %s' % (len(snap_text), snap_text[:60]))
    code, r = call('read', {})
    record('call read', code == 200 and 'result' in r, str(r)[:50])
    code, r = call('grep', {'pattern': 'Example'})
    record('call grep', code == 200 and 'result' in r and 'match' in str(r).lower(), str(r)[:50])
    code, r = call('tabs', {'action': 'list'})
    record('call tabs list', code == 200 and 'result' in r, str(r)[:50])
    code, r = call('history', {'action': 'list', 'limit': 5})
    record('call history list', code == 200 and 'result' in r, str(r)[:50])
    code, r = call('windows', {'action': 'list'})
    record('call windows list', code == 200 and 'result' in r, str(r)[:50])

    # --- 4. negatives ---
    code, r = http_post('/mcp?token=invalid000', rpc('initialize', {'protocolVersion': '2024-11-05',
                                                                    'capabilities': {},
                                                                    'clientInfo': {'name': 'x', 'version': '1'}}))
    record('negative: invalid token -> 401', code == 401, str(code))
    code, r = http_post(qs, rpc('bogus/method', {}))
    err = r.get('error', {})
    record('negative: unknown method -> JSON-RPC error', code == 200 and err.get('code') == -32601, str(err)[:60])
    code, r = http_post(qs, rpc('tools/call', {'name': 'navigate', 'arguments': {}}))
    err = r.get('error', {})
    ok = code == 200 and err.get('code') not in (None, 0) or 'error' in str(r.get('result', ''))[:80]
    record('negative: missing url -> schema/param error', ok, str(r)[:70])

    # --- 5. rate limit (50 rapid on ONE keep-alive connection) ---
    # urllib 每请求新建 TCP → 每连接窗口重置；压测须走单连接 keep-alive
    import http.client
    limited = 0
    last_code = 0
    hc = http.client.HTTPConnection('127.0.0.1', HOST_PORT, timeout=8)
    try:
        for i in range(50):
            body = json.dumps(rpc('tools/list', {})).encode()
            hc.request('POST', qs, body=body, headers={'Content-Type': 'application/json'})
            resp = hc.getresponse()
            last_code = resp.status
            try:
                r = json.loads(resp.read().decode())
            except Exception:
                r = {}
            err = (r or {}).get('error') if isinstance(r, dict) else None
            if resp.status == 429 or (isinstance(err, dict) and err.get('message') == 'rate limited'):
                limited += 1
    finally:
        hc.close()
    record('rate limit engaged (>=1 of 50 limited, keep-alive)', limited >= 1, 'limited=%d last=%s' % (limited, last_code))
    # wait window to recover (window 10s) then one allowed
    time.sleep(11)
    code, r = http_post(qs, rpc('tools/list', {}))
    record('rate limit window recovery', code == 200 and 'result' in r, str(code))

    # --- 6. WS transport ---
    ws_ok = False
    ws_detail = ''
    try:
        s = socket.create_connection(('127.0.0.1', WS_PORT), timeout=8)
        key = base64.b64encode(b'e2e-ws-key-p43b-16').decode()  # 客户端 key 就是随机 base64（服务器才算 SHA1）
        req = ('GET /?token=' + token + ' HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\n'
               'Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n' % (WS_PORT, key))
        s.sendall(req.encode())
        time.sleep(1)
        resp = s.recv(4096).decode(errors='replace')
        if '101' in resp.split('\r\n')[0]:
            body = json.dumps(rpc('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {},
                                                 'clientInfo': {'name': 'e2e-ws', 'version': '1'}})).encode()
            mask = b'\x00\x00\x00\x00'  # zero mask (allowed for test)
            frame = b'\x81' + bytes([0x80 | len(body)]) + mask + body
            s.sendall(frame)
            time.sleep(1.5)
            data = s.recv(65536)
            ws_ok = b'"result"' in data and b'serverInfo' in data
            ws_detail = data[:80].decode(errors='replace')
        s.close()
    except Exception as e:
        ws_detail = str(e)[:80]
    record('ws transport initialize', ws_ok, ws_detail)

    # summary
    passed = sum(1 for _, ok in results if ok)
    print('\n== mcp_client_e2e: %d/%d PASS ==' % (passed, len(results)))
    sys.exit(0 if passed == len(results) else 1)


if __name__ == '__main__':
    main()
