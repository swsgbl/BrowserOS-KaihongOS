#!/usr/bin/env python3
"""P59-A/D DECISIVE2: one session: tab->wps->eval coords->click->shot. Robust eval-result parsing."""
import sys, time, subprocess, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
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

r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'https://www.wps.cn'})
time.sleep(15)

# sanity: page alive?
r = call_tool(qs, sid, 'evaluate_in_page', {'expression': "JSON.stringify({n:document.querySelectorAll('*').length,t:document.title})"}, timeout=60)
raw = result_text(r)
print('sanity:', raw[:400])

JS = ("JSON.stringify((function(){var els=document.querySelectorAll('a,button,span,div');"
      "var out=[];for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
      "if(t==='在线使用'){var r=els[i].getBoundingClientRect();"
      "out.push({x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});"
      "if(out.length>2)break;}}return out})())")
r = call_tool(qs, sid, 'evaluate_in_page', {'expression': JS}, timeout=60)
raw = result_text(r)
print('eval raw:', raw[:500])

# result envelope: {"expression":...,"result":"{\"ok\":true,\"result\":\"...\"}"} (string-in-string)
coords = []
try:
    outer = json.loads(raw)
    res1 = outer.get('result', '')
    if isinstance(res1, str):
        res1 = json.loads(res1)          # -> {ok, result}
        res2 = res1.get('result', '')
        if isinstance(res2, str):
            coords = json.loads(res2)    # -> [{x,y},...]
        elif isinstance(res2, list):
            coords = res2
except Exception as e:
    print('parse err', e)
print('coords =', coords)

if coords:
    b = coords[0]
    print('CLICK at', b['x'], b['y'])
    sh('uinput -T -c %d %d' % (b['x'], b['y']))
    time.sleep(3)
    sh('snapshot_display -f /data/local/tmp/p59_menu7.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_menu7.jpeg', EV + r"\p59_wps_menu_decisive2.jpeg"], capture_output=True)
    print('SAVED decisive2')
p59_keepalive.stop()
