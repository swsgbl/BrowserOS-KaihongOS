#!/usr/bin/env python3
"""P59-A/D DECISIVE: clean restart -> MCP tab -> wps.cn -> evaluate coords -> native click -> dropdown shot."""
import sys, time, subprocess, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
p59_keepalive.start()
time.sleep(2)

# fresh single-tab state
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('rm -f /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/tabs.json')
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)

token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'https://www.wps.cn'})
t = result_text(r)
print('new:', t[:160])
time.sleep(15)

r = call_tool(qs, sid, 'snapshot', {}, timeout=90)
txt = result_text(r)
print('snapshot len', len(txt), '在线使用 at', txt.find('在线使用'))
with open(EV + r"\p59_decisive_snap.txt", 'w', encoding='utf-8') as f:
    f.write(txt)

JS = ("(function(){var els=document.querySelectorAll('a,button,span,div');"
      "var out=[];for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
      "if(t==='在线使用'){var r=els[i].getBoundingClientRect();"
      "out.push({x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});"
      "if(out.length>2)break;}}return JSON.stringify(out)})()")
r = call_tool(qs, sid, 'evaluate_in_page', {'expression': JS}, timeout=60)
txt = result_text(r)
print('eval:', txt[:300])

coords = []
try:
    env = json.loads(txt)
    raw = (env.get('data', {}) or {}).get('result', '')
    if isinstance(raw, str) and raw:
        inner = json.loads(raw)
        if isinstance(inner, dict) and 'result' in inner:
            coords = json.loads(inner['result'])
        elif isinstance(inner, list):
            coords = inner
except Exception as e:
    print('parse:', e)
print('coords:', coords)

if coords:
    b = coords[0]
    print('CLICK at', b)
    sh('uinput -T -c %d %d' % (b['x'], b['y']))
    time.sleep(3)
    sh('snapshot_display -f /data/local/tmp/p59_menu6.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_menu6.jpeg', EV + r"\p59_wps_menu_decisive.jpeg"], capture_output=True)
    # also try hover-menu on nav items
    print('saved')
p59_keepalive.stop()
