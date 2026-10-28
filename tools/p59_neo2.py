import sys, json, time
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh

CFG = '/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json'
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
cfg = sh('cat ' + CFG)
print('cfg now:', cfg[:120], '...')
j = json.loads(cfg)
j['isNeoMode'] = True
new = json.dumps(j, ensure_ascii=False)
# write via base64 to dodge shell quoting entirely
import base64
b64 = base64.b64encode(new.encode('utf-8')).decode('ascii')
sh("echo %s | base64 -d > %s" % (b64, CFG))
time.sleep(0.5)
chk = sh('cat ' + CFG)
print('neo set:', '"isNeoMode":true' in chk)
print('len check:', len(chk), 'vs', len(new))
