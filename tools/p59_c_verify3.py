#!/usr/bin/env python3
"""P59-C verify v3: force browser foreground, sidebar settings -> skills -> back."""
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
time.sleep(2)
# bring browser to front
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('rm -f /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/tabs.json')
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(8)

# settings via sidebar (69,611)
sh('uinput -T -c 69 611')
time.sleep(3)
j = dump_layout('p59_l_set.json')
print('set page?', bool(find_text(j, '设置') if j else []), 'settings title hits:', len(find_text(j, '默认搜索引擎') if j else []))
if j:
    hits = find_text(j, '技能') or find_text(j, 'Skills')
    print('skills entry:', json.dumps(hits[:2], ensure_ascii=False))
    if hits:
        c = bc(hits[0]['b'])
        sh('uinput -T -c %d %d' % c)
        time.sleep(3)
        j2 = dump_layout('p59_l_skills.json')
        if j2:
            t = find_text(j2, '技能') or find_text(j2, 'Skills')
            print('skills page:', json.dumps(t[:2], ensure_ascii=False))
            sh('snapshot_display -f /data/local/tmp/p59_sk.jpeg')
            subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_sk.jpeg', EV + '\\p59_skills_page.jpeg'], capture_output=True)
            # find back icon images top-left
            imgs = []

            def wi(n):
                if not isinstance(n, dict):
                    return
                a = n.get('attributes') or n
                if a.get('type', '') == 'Image':
                    bb = a.get('bounds', '')
                    cc = bc(bb) or (0, 0)
                    if cc[0] < 120 and cc[1] < 220:
                        imgs.append(bb)
                for ch in (n.get('children') or []):
                    wi(ch)
            wi(j2)
            print('back candidates:', imgs[:3])
p59_keepalive.stop()
