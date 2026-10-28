#!/usr/bin/env python3
"""P59-A/D DECISIVE5: synthetic events on nav (mouseover+click on WPS Office nav trigger) -> verify menu DOM visible."""
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


def eval_js(js):
    r = call_tool(qs, sid, 'evaluate_in_page', {'expression': js}, timeout=60)
    raw = result_text(r)
    try:
        o = json.loads(raw)
        r1 = json.loads(o['result'])
        r2 = r1.get('result', '')
        return json.loads(r2) if isinstance(r2, str) else r2
    except Exception:
        return None


# viewport info first
info = eval_js("JSON.stringify({iw:window.innerWidth,ih:window.innerHeight,dpr:window.devicePixelRatio,ua:navigator.userAgent.slice(0,60)})")
print('viewport:', info)

# find the hover-trigger of the nav dropdown: elements with mouseenter handlers are typically li.nav-item
# dispatch pointerover+mouseover on 'WPS Office' nav item, then check nav-panel visibility
JS_HOVER = ("JSON.stringify((function(){"
            "var els=document.querySelectorAll('a,button,span,div,li');var tgt=null;"
            "for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
            "if(t==='WPS Office'){var r=els[i].getBoundingClientRect();if(r.width>0){tgt=els[i];break;}}}"
            "if(!tgt)return 'no-target';"
            "['pointerover','mouseover','mouseenter'].forEach(function(tn){"
            "tgt.dispatchEvent(new MouseEvent(tn,{bubbles:true,cancelable:true,view:window}));});"
            "return 'hover-dispatched'})())")
print(eval_js(JS_HOVER))
time.sleep(2)

# check nav panel items now visible (产品 dropdown contains WPS Office/WPS 365/Comate...)
vis = eval_js("JSON.stringify((function(){var els=document.querySelectorAll('a,div,li');"
              "var hits=[];for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
              "if((t==='WPS 365'||t==='WPS Comate'||t.indexOf('WPS 超级会员')===0||t==='WPS AI')&&t.length<20){"
              "var r=els[i].getBoundingClientRect();if(r.width>0&&r.height>0){hits.push(t.slice(0,16));}}}"
              "return hits.slice(0,8)})())")
print('nav panel visible items:', json.dumps(vis, ensure_ascii=False))

sh('snapshot_display -f /data/local/tmp/p59_m_h.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_m_h.jpeg', EV + r"\p59_wps_nav_hover.jpeg"], capture_output=True)
print('shot saved')
p59_keepalive.stop()
