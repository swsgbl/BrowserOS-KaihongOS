#!/usr/bin/env python3
"""P59-A/D final2: use evaluate_in_page to get 在线使用 button live coordinates -> native click -> dropdown screenshot."""
import sys, time, subprocess, json
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"
p59_keepalive.start()
time.sleep(2)

token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

# check tabs & active state
r = call_tool(qs, sid, 'tabs', {'action': 'list'})
print('tabs:', result_text(r)[:400])

# find the wps tab; navigate active tab if it's the wps one
r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'https://www.wps.cn'})
print('new:', result_text(r)[:160])
time.sleep(15)

# get live coordinates of the 在线使用 button via evaluate_in_page
JS = ("(function(){var els=document.querySelectorAll('a,button,span,div');"
      "var out=[];for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
      "if(t==='在线使用'){var r=els[i].getBoundingClientRect();"
      "out.push({t:t.slice(0,10),x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2),w:Math.round(r.width),h:Math.round(r.height)});"
      "if(out.length>3)break;}}return JSON.stringify(out)})()")
r = call_tool(qs, sid, 'evaluate_in_page', {'expression': JS}, timeout=60)
txt = result_text(r)
print('eval:', txt[:500])
with open(EV + r"\p59_wps_btn_coords.txt", 'w', encoding='utf-8') as f:
    f.write(txt)

coords = []
try:
    env = json.loads(txt)
    raw = env.get('data', {}).get('result', '') or env.get('result', '')
    if isinstance(raw, str) and raw.startswith('['):
        coords = json.loads(raw)
    elif isinstance(raw, list):
        coords = raw
except Exception as e:
    print('parse fail', e)

if coords:
    b = coords[0]
    x, y = b['x'], b['y']
    print('clicking at', x, y)
    sh('uinput -T -c %d %d' % (x, y))
    time.sleep(2.5)
    sh('snapshot_display -f /data/local/tmp/p59_menu4.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_menu4.jpeg', EV + r"\p59_wps_menu_click_eval.jpeg"], capture_output=True)
    print('saved menu screenshot')
else:
    print('no coords found')
p59_keepalive.stop()
