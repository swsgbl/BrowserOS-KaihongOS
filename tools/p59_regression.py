#!/usr/bin/env python3
"""P59-F: MCP regression sample — tabs/navigate/snapshot/evaluate/read on live device (post-fix build)."""
import sys, time, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
results = []


def step(name, ok, detail=''):
    results.append((name, ok, detail[:90]))
    print(('PASS ' if ok else 'FAIL ') + name + (' | ' + detail[:90] if detail else ''))


p59_keepalive.start()
time.sleep(2)

sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('rm -f /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/tabs.json')
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)

token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)
step('mcp initialize', bool(sid))

r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'https://example.com'})
t = result_text(r)
step('tabs.new example.com', '"tabId"' in t, t[:80])
time.sleep(8)

r = call_tool(qs, sid, 'snapshot', {}, timeout=60)
t = result_text(r)
step('snapshot example.com', 'Example Domain' in t, 'len=%d' % len(t))

r = call_tool(qs, sid, 'evaluate_in_page', {'expression': "document.title"}, timeout=60)
t = result_text(r)
step('evaluate_in_page', 'Example' in t, t[:80])

r = call_tool(qs, sid, 'navigate', {'url': 'https://www.baidu.com'}, timeout=90)
t = result_text(r)
step('navigate baidu', 'baidu' in t, t[:80])
time.sleep(8)
r = call_tool(qs, sid, 'snapshot', {}, timeout=60)
t = result_text(r)
step('snapshot baidu', ('百度' in t) or ('baidu' in t.lower()), 'len=%d' % len(t))

r = call_tool(qs, sid, 'tabs', {'action': 'list'})
t = result_text(r)
step('tabs.list', '"tabs"' in t, t[:70])

r = call_tool(qs, sid, 'history', {})
t = result_text(r)
step('history', '"error"' not in t, t[:70])

with open(EV + r"\p59_regression_sample.txt", 'w', encoding='utf-8') as f:
    for n, ok, d in results:
        f.write('%s %s | %s\n' % ('PASS' if ok else 'FAIL', n, d))
print('---- %d/%d passed' % (sum(1 for _, ok, _ in results if ok), len(results)))
p59_keepalive.stop()
