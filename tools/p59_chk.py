import sys
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh
chk = sh('cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/config.json')
print(repr(chk[:600]))
