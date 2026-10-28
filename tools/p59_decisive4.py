#!/usr/bin/env python3
"""P59-A/D DECISIVE4: verify menu opens — dispatch real click() in page JS, then DOM-check the dropdown visibility."""
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


# 1) native click at 更多下载 (322,296) — with mousedown+mouseup semantics via uinput -T -d/-u
sh('uinput -T -d 322 296')
time.sleep(0.3)
sh('uinput -T -u 322 296')
time.sleep(2)

state = eval_js("JSON.stringify((function(){var els=document.querySelectorAll('a,button,span,div,li');"
                "var hits=[];for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
                "if((t.indexOf('Windows版')===0||t.indexOf('Mac版')===0||t.indexOf('Linux版')===0||t.indexOf('鸿蒙版')===0)&&t.length<30){"
                "var r=els[i].getBoundingClientRect();var st=getComputedStyle(els[i]);"
                "hits.push({t:t.slice(0,12),vis:st.display!+'none'&&r.height>0,x:Math.round(r.x),y:Math.round(r.y)});}}"
                "return hits.slice(0,10)})())".replace("!+", "!="))
print('after native click, dl items:', json.dumps(state, ensure_ascii=False)[:600])

# 2) JS-dispatched click on 更多下载
res = eval_js("JSON.stringify((function(){var els=document.querySelectorAll('a,button,span,div');"
              "for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
              "if(t.indexOf('更多下载')===0){els[i].click();return 'clicked:'+t.slice(0,10);}}return 'notfound'})())")
print('js click:', res)

time.sleep(2)
sh('snapshot_display -f /data/local/tmp/p59_m_js.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_m_js.jpeg', EV + r"\p59_wps_menu_js.jpeg"], capture_output=True)

state2 = eval_js("JSON.stringify((function(){var els=document.querySelectorAll('a,button,span,div,li');"
                 "var hits=[];for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
                 "if((t.indexOf('Windows版')===0||t.indexOf('Mac版')===0||t.indexOf('Linux版')===0||t.indexOf('鸿蒙版')===0)&&t.length<30){"
                 "var r=els[i].getBoundingClientRect();var st=getComputedStyle(els[i]);"
                 "hits.push({t:t.slice(0,12),vis:(st.display!='none'&&r.height>0),x:Math.round(r.x),y:Math.round(r.y)});}}"
                 "return hits.slice(0,10)})())")
print('after js click, dl items:', json.dumps(state2, ensure_ascii=False)[:600])
p59_keepalive.stop()
