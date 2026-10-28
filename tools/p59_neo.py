import sys, json, time
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh

CFG = '/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json'
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
cfg = sh('cat ' + CFG)
j = json.loads(cfg)
j['isNeoMode'] = True
new = json.dumps(j, ensure_ascii=False).replace("'", "'\\''")
sh("echo '%s' > %s" % (new, CFG))
time.sleep(0.5)
chk = sh('cat ' + CFG)
print('neo set:', '"isNeoMode":true' in chk)
print(sh('aa start -a EntryAbility -b com.browseros.kaihong'))
