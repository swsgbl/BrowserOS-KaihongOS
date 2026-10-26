#!/usr/bin/env python3
"""P49 B4 probe: navigate -> snapshot -> read full bodies."""
import json
import subprocess
import sys
import time
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"


def sh(cmd, tmo=30):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=tmo, errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()


token = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip().splitlines()[-1]
qs = '/mcp?token=' + token
print('token tail:', token[-4:])


def post(body, timeout=15):
    req = urllib.request.Request('http://127.0.0.1:19222' + qs, data=json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def call(name, args, i=[100]):
    i[0] += 1
    return post({'jsonrpc': '2.0', 'id': i[0], 'method': 'tools/call', 'params': {'name': name, 'arguments': args}})


r = call('navigate', {'url': 'https://example.com'})
print('navigate:', json.dumps(r, ensure_ascii=False)[:300])
time.sleep(8)
r = call('snapshot', {})
s = json.dumps(r, ensure_ascii=False)
print('snapshot len:', len(s))
print('snapshot:', s[:600])
r = call('read', {})
s = json.dumps(r, ensure_ascii=False)
print('read:', s[:500])
# 设备侧检查：活动 tab 的 url
print('device url:', sh('hilog -x -z 2000 | tail -200', tmo=15)[:100])
