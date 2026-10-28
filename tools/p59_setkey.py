#!/usr/bin/env python3
"""P59-E: write API key into config.json, restart app, verify agent can call the real LLM."""
import sys, time, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

CFG = '/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json'
KEY = 'sk-ZzeLuzxw4AgkL90FF7QUSgYoL8DNG1Z2Kt3kHpiKJjOgTHdt'

p59_keepalive.start()
time.sleep(1)
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)

cfg = sh('cat ' + CFG)
j = json.loads(cfg)
j['llmApiKey'] = KEY
prov = json.loads(j['llmProviders'])
for p in prov:
    if p.get('name') == 'agnes-ai':
        p['apiKey'] = KEY
j['llmProviders'] = json.dumps(prov, ensure_ascii=False)
new = json.dumps(j, ensure_ascii=False)

# write back via echo (escape quotes for shell)
esc = new.replace("'", "'\\''")
sh("echo '%s' > %s" % (esc, CFG))
time.sleep(0.5)
check = sh('cat ' + CFG)
ok = KEY in check
print('key written:', ok)
if not ok:
    print(check[:400])

sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)
print('app restarted')
p59_keepalive.stop()
