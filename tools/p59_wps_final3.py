#!/usr/bin/env python3
"""P59-A/D final3: navigate ACTIVE on-screen tab via omnibox tap + evaluate coords + click."""
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

# Which tab does THIS session route to? snapshot it
r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'https://www.wps.cn'})
t = result_text(r)
print('new:', t[:160])
tid = json.loads(t).get('tabId', '')
time.sleep(15)

r = call_tool(qs, sid, 'snapshot', {}, timeout=90)
txt = result_text(r)
print('snapshot len', len(txt), '在线使用 at', txt.find('在线使用'))

# P51 routes session tools to owned tab; evaluate too:
JS = ("(function(){var els=document.querySelectorAll('a,button,span,div');"
      "var out=[];for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
      "if(t==='在线使用'){var r=els[i].getBoundingClientRect();"
      "out.push({x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});"
      "if(out.length>2)break;}}return JSON.stringify(out)})()")
r = call_tool(qs, sid, 'evaluate_in_page', {'expression': JS, 'tabId': tid}, timeout=60)
txt = result_text(r)
print('eval:', txt[:400])
with open(EV + r"\p59_wps_eval2.txt", 'w', encoding='utf-8') as f:
    f.write(txt)
p59_keepalive.stop()
