import sys, json, time
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh

CFG = '/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json'
KEY = 'sk-ZzeLuzxw4AgkL90FF7QUSgYoL8DNG1Z2Kt3kHpiKJjOgTHdt'

# app is running with neo=true now. force-stop, write key, start, wait, read
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
import base64
b64 = base64.b64encode(new.encode('utf-8')).decode('ascii')
sh("echo %s | base64 -d > %s" % (b64, CFG))
time.sleep(0.5)
before = sh('cat ' + CFG)
print('before start: key present =', KEY in before)

sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(10)
after = sh('cat ' + CFG)
print('after start: key present =', KEY in after)
if KEY not in after:
    print('LOST! cfg after:', after[:400])
