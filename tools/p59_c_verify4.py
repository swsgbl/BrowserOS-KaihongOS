#!/usr/bin/env python3
"""P59-C verify v4: dismiss stale sensitive dialog -> settings -> skills -> back."""
import sys, time, subprocess, json, re
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"


def dump_layout(name):
    out = sh('uitest dumpLayout')
    m = re.search(r'saved to:(\S+)', out)
    if not m:
        return None
    subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\' + name], capture_output=True)
    try:
        return json.load(open(EV + '\\' + name, encoding='utf-8'))
    except Exception:
        return None


def find_text(root, needle):
    res = []

    def walk(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or n
        t = a.get('text', '') or ''
        if needle in t:
            res.append({'t': t[:30], 'b': a.get('bounds', '')})
        for c in (n.get('children') or []):
            walk(c)
    walk(root)
    return res


def bc(b):
    m = re.findall(r'\d+', b)
    return ((int(m[0]) + int(m[2])) // 2, (int(m[1]) + int(m[3])) // 2) if len(m) >= 4 else None


p59_keepalive.start()
time.sleep(1)

# fresh app state (dialog dies with the process)
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('rm -f /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/tabs.json')
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)

j = dump_layout('p59_l_home2.json')
if j:
    dlg = find_text(j, '敏感操作确认')
    if dlg:
        rej = find_text(j, '拒绝')
        if rej:
            c = bc(rej[0]['b'])
            sh('uinput -T -c %d %d' % c)
            time.sleep(2)
            print('dismissed dialog at', c)

# now settings
sh('uinput -T -c 69 611')
time.sleep(3)
j = dump_layout('p59_l_set2.json')
if j:
    hits = find_text(j, '技能') or find_text(j, 'Skills')
    print('skills entry:', json.dumps(hits[:2], ensure_ascii=False))
    if hits:
        c = bc(hits[0]['b'])
        sh('uinput -T -c %d %d' % c)
        time.sleep(3)
        j2 = dump_layout('p59_l_skills2.json')
        if j2:
            t = find_text(j2, '技能') or find_text(j2, 'Skills')
            print('ON SKILLS PAGE:', json.dumps(t[:3], ensure_ascii=False))
            imgs = []

            def wi(n):
                if not isinstance(n, dict):
                    return
                a = n.get('attributes') or n
                if a.get('type', '') == 'Image':
                    bb = a.get('bounds', '')
                    cc = bc(bb) or (0, 0)
                    if cc[0] < 130 and cc[1] < 230:
                        imgs.append(bb)
                for ch in (n.get('children') or []):
                    wi(ch)
            wi(j2)
            print('BACK BTN candidates:', imgs[:3])
            sh('snapshot_display -f /data/local/tmp/p59_sk2.jpeg')
            subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_sk2.jpeg', EV + '\\p59_skills_page2.jpeg'], capture_output=True)
            # tap back candidate and confirm we leave the page
            if imgs:
                c = bc(imgs[0])
                sh('uinput -T -c %d %d' % c)
                time.sleep(2.5)
                j3 = dump_layout('p59_l_afterback.json')
                if j3:
                    still = find_text(j3, 'Skills 台账') or find_text(j3, 'Runs')
                    gone = find_text(j3, '默认搜索引擎') or find_text(j3, '搜索引擎')
                    print('after back: still-skills=%s, on-settings=%s' % (bool(still), bool(gone)))
p59_keepalive.stop()
