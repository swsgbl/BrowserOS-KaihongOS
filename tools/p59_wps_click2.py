#!/usr/bin/env python3
"""P59-A/D full verify v2: tab -> wps.cn -> find 在线使用 ref -> act click -> screenshot."""
import sys, time, json, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"


def snap_refs(qs, sid):
    r = call_tool(qs, sid, 'snapshot', {}, timeout=90)
    txt = result_text(r)
    # MCP response envelope: {"status":"success","data":{"content":...,"refs":[...]}} inside content[0].text
    refs = []
    try:
        env = json.loads(txt)
        data = env.get('data', {})
        refs = data.get('refs', [])
    except Exception:
        pass
    return txt, refs


p59_keepalive.start()
time.sleep(2)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(4)

token = get_token()
qs = '/mcp?token=' + token
sid = session(qs)

r = call_tool(qs, sid, 'tabs', {'action': 'new', 'url': 'about:blank'})
print('tabs.new:', result_text(r)[:120])
time.sleep(4)

r = call_tool(qs, sid, 'navigate', {'url': 'https://www.wps.cn'}, timeout=120)
print('navigate:', result_text(r)[:160])
time.sleep(12)

txt, refs = snap_refs(qs, sid)
with open(EV + r"\p59_wps_snapshot3.txt", 'w', encoding='utf-8') as f:
    f.write(txt)
print('snap len', len(txt), 'refs', len(refs))

target = None
for ref in refs:
    s = json.dumps(ref, ensure_ascii=False)
    if '在线使用' in s:
        print('REF:', s[:220])
        target = ref
        break

if target is not None:
    rid = str(target.get('ref', ''))
    r = call_tool(qs, sid, 'act', {'action': 'click', 'ref': rid}, timeout=60)
    print('act.click:', result_text(r)[:250])
    time.sleep(3)
    sh('snapshot_display -f /data/local/tmp/p59_menu1.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_menu1.jpeg',
                    EV + r"\p59_wps_menu_open.jpeg"], capture_output=True)
    txt2, _ = snap_refs(qs, sid)
    with open(EV + r"\p59_wps_snapshot_after_click.txt", 'w', encoding='utf-8') as f:
        f.write(txt2)
    print('after-click snap len', len(txt2))
else:
    print('NO REF — dumping refs sample:')
    for ref in refs[:12]:
        print(json.dumps(ref, ensure_ascii=False)[:160])
p59_keepalive.stop()
