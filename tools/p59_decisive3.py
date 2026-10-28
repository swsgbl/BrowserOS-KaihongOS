#!/usr/bin/env python3
"""P59-A/D DECISIVE3: click the top-nav 'WPS Office v' chevron (dropdown) + 更多下载 chevron; shots after each."""
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


# find all elements whose text contains 在线使用 OR chevron/more-download markers, with coords
JS = ("JSON.stringify((function(){var els=document.querySelectorAll('a,button,span,div');"
      "var out=[];for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();"
      "if((t==='在线使用'||t.indexOf('更多下载')===0||t==='WPS Office'||t.indexOf('产品')===0||t.indexOf('下载')===0)&&t.length<25){"
      "var r=els[i].getBoundingClientRect();if(r.width>0&&r.height>0){"
      "out.push({t:t.slice(0,14),x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});}}"
      "if(out.length>8)break;}return out})())")
found = eval_js(JS)
print('found:', json.dumps(found, ensure_ascii=False))

shots = 0
if found:
    # click WPS Office chevron first (top nav dropdown)
    for cand in found:
        if cand['t'] == 'WPS Office':
            sh('uinput -T -c %d %d' % (cand['x'], cand['y']))
            time.sleep(2.5)
            sh('snapshot_display -f /data/local/tmp/p59_m_nav.jpeg')
            subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_m_nav.jpeg', EV + r"\p59_wps_nav_open.jpeg"], capture_output=True)
            shots += 1
            print('nav shot saved', cand)
            break
    for cand in found:
        if cand['t'].startswith('更多下载'):
            sh('uinput -T -c %d %d' % (cand['x'], cand['y']))
            time.sleep(2.5)
            sh('snapshot_display -f /data/local/tmp/p59_m_dl.jpeg')
            subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_m_dl.jpeg', EV + r"\p59_wps_dl_open.jpeg"], capture_output=True)
            shots += 1
            print('dl shot saved', cand)
            break
print('shots:', shots)
p59_keepalive.stop()
