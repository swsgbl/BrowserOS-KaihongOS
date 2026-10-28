#!/usr/bin/env python3
"""P59-A/D FINAL VERIFY: desktop UA -> wps.cn desktop layout -> nav menu opens (DOM-visible + screenshot)."""
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
time.sleep(16)


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


info = eval_js("JSON.stringify({iw:window.innerWidth,ua:navigator.userAgent.slice(0,80)})")
print('viewport/UA:', info)

# desktop layout? nav contains 产品下载 links
nav = eval_js("JSON.stringify((function(){var els=document.querySelectorAll('a');var hits=[];"
              "for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
              "if((t==='WPS Office'||t==='产品'||t==='下载'||t.indexOf('在线使用')>=0)&&t.length<12){hits.push(t);}}"
              "return hits.slice(0,8)})())")
print('nav items:', json.dumps(nav, ensure_ascii=False))

# click 在线使用 (desktop: opens dropdown OR navigates) — use element.click() first, then check for dropdown panels
res = eval_js("JSON.stringify((function(){var els=document.querySelectorAll('a,button,span,div');"
              "for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
              "if(t==='在线使用'){var r=els[i].getBoundingClientRect();if(r.width>0){"
              "els[i].click();return JSON.stringify({x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});}}}"
              "return 'notfound'})())")
print('click 在线使用:', res)
time.sleep(3)

# dropdown panel check: platform list items visible?
vis = eval_js("JSON.stringify((function(){var els=document.querySelectorAll('a,div,li,span');var hits=[];"
              "for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
              "if((t.indexOf('Windows')===0||t.indexOf('Mac')===0||t.indexOf('Linux')===0||t.indexOf('鸿蒙')===0||t.indexOf('Android')===0||t.indexOf('iOS')===0)&&t.length<20){"
              "var r=els[i].getBoundingClientRect();if(r.width>0&&r.height>0){hits.push(t.slice(0,14));}}}"
              "return hits.slice(0,10)})())")
print('visible dl items:', json.dumps(vis, ensure_ascii=False))

sh('snapshot_display -f /data/local/tmp/p59_final.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_final.jpeg', EV + r"\p59_wps_final_desktop.jpeg"], capture_output=True)
print('FINAL SHOT SAVED')
p59_keepalive.stop()
