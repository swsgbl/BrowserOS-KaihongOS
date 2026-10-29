#!/usr/bin/env python3
"""P68: targeted verification of the three app-side bug fixes.

1. wait tool: ms branch returns {ms, waited:true} (no misleading result:null);
   selector branch returns explicit found flag.
2. BCPEngine race timers: executeJS/evaluate success paths no longer leak the
   5s timeout timers (verified indirectly: 5 rapid evaluate calls all succeed
   and stay under the inject timeout - no late __BCP_TIMEOUT__ interleave).
3. read transitional settle: navigate -> immediate read on the fresh tab; with
   the P68 retry the read must not return the bare null-body error when the
   page settles within the window (example.com loads fast enough).
"""
import json
import subprocess
import sys
import time
import urllib.request
import urllib.error

sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
HOST_PORT = 19222
results = []


def sh(cmd, tmo=60):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def record(name, ok, detail=''):
    results.append((name, ok))
    print(('[PASS] ' if ok else '[FAIL] ') + name + ((' — ' + detail) if detail else ''))


SESSION = [None]


def http_post(path_qs, body, timeout=15, session=None):
    headers = {'Content-Type': 'application/json'}
    if session:
        headers['Mcp-Session-Id'] = session
    req = urllib.request.Request('http://127.0.0.1:%d%s' % (HOST_PORT, path_qs),
                                 data=json.dumps(body).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            sid = resp.headers.get('Mcp-Session-Id')
            if sid:
                SESSION[0] = sid
            raw = resp.read().decode()
            try:
                return resp.status, json.loads(raw) if raw.strip() else {}
            except Exception:
                return resp.status, {}
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, {}


def rpc(method, params, _id=[0]):
    _id[0] += 1
    return {'jsonrpc': '2.0', 'id': _id[0], 'method': method, 'params': params}


def tool_text(resp):
    """extract the MCP content[0].text payload as a dict (or raw string)"""
    try:
        txt = resp['result']['content'][0]['text']
        try:
            return json.loads(txt)
        except Exception:
            return txt
    except Exception:
        return {}


def main():
    token = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt').strip().splitlines()[-1]
    qs = '/mcp?token=' + token

    code, init = http_post(qs, rpc('initialize', {'protocolVersion': '2024-11-05',
                                                  'capabilities': {},
                                                  'clientInfo': {'name': 'p68-verify', 'version': '1'}}))
    assert code == 200, 'initialize failed: %s' % init
    http_post(qs, {'jsonrpc': '2.0', 'method': 'notifications/initialized'}, session=SESSION[0])

    # P51: session must own a tab before any page tool works
    code, r = http_post(qs, rpc('tools/call', {'name': 'tabs', 'arguments': {'action': 'new'}}), session=SESSION[0])
    assert code == 200, 'tabs new failed: %s' % r

    def call(name, args):
        return http_post(qs, rpc('tools/call', {'name': name, 'arguments': args}), session=SESSION[0])

    # --- 1. wait ms branch: waited:true, NO result field ---
    code, r = call('wait', {'ms': 300})
    data = tool_text(r)
    ok = code == 200 and isinstance(data, dict) and data.get('waited') is True and 'result' not in data
    record('wait ms -> {ms, waited:true} (no result:null)', ok, json.dumps(data, ensure_ascii=False)[:100])

    # --- 1b. wait selector branch: miss -> explicit error naming the miss (P68: honest miss beats false found) ---
    code, r = call('wait', {'selector': '[data-bcp-ref="no-such-ref-xyz"]', 'timeout': 800})
    data = tool_text(r)
    rpc_err = ''
    try:
        rpc_err = r.get('error', {}).get('message', '')
    except Exception:
        pass
    ok = (isinstance(data, dict) and data.get('found') is False) or ('not found within' in rpc_err)
    record('wait selector miss -> explicit miss (found:false or error)', ok, (rpc_err or str(data))[:100])

    # --- 2. race-timer hygiene: 5 rapid evaluates, all settle fast ---
    t0 = time.time()
    ok_all = True
    for i in range(5):
        code, r = call('evaluate_in_page', {'expression': '1+1'})
        d = tool_text(r)
        if not (code == 200 and isinstance(d, dict) and '2' in str(d.get('result', ''))):
            ok_all = False
    dt = time.time() - t0
    record('5x evaluate fast-settle (no leaked-timer interleave)', ok_all and dt < 10, 'dt=%.1fs' % dt)

    # --- 3. read transitional settle: navigate then immediate read ---
    code, r = call('tabs', {'action': 'new'})
    d = tool_text(r)
    tid = d.get('tabId', '') if isinstance(d, dict) else ''
    code, _ = call('navigate', {'url': 'https://example.com', 'tabId': tid})
    time.sleep(0.3)  # deliberately inside the 3s post-nav window
    code, r = call('read', {'tabId': tid})
    raw = json.dumps(r, ensure_ascii=False)
    bad = 'empty snapshot for routed tab' in raw
    record('read right after navigate -> no bare empty-snapshot error', code == 200 and not bad, raw[:110])

    # cleanup: close the tab we opened
    call('tabs', {'action': 'close', 'tabId': tid})

    passed = sum(1 for _, ok in results if ok)
    print('\n== p68_verify: %d/%d PASS ==' % (passed, len(results)))
    sys.exit(0 if passed == len(results) else 1)


if __name__ == '__main__':
    main()
