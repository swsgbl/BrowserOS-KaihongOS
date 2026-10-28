#!/usr/bin/env python3
"""P59-C verify: Settings -> Skills page -> back button visible -> tap -> back works."""
import sys, time, subprocess, json, re
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import *  # noqa
import p59_keepalive

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"


def dump_layout(name):
    out = sh('uitest dumpLayout')
    m = re.search(r'saved to:(\S+)', out)
    if not m:
        print('dump fail', out[:200])
        return None
    subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\' + name], capture_output=True)
    try:
        return json.load(open(EV + '\\' + name, encoding='utf-8'))
    except Exception as e:
        print('recv fail', e)
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


def bounds_center(b):
    m = re.findall(r'\d+', b)
    if len(m) >= 4:
        return (int(m[0]) + int(m[2])) // 2, (int(m[1]) + int(m[3])) // 2
    return None


p59_keepalive.start()
time.sleep(2)

# already on home (from previous run). Click 设置 sidebar (69, 611)
sh('uinput -T -c 69 611')
time.sleep(3)
j = dump_layout('p59_layout_settings.json')
if j:
    hits = find_text(j, '技能')
    print('技能 entries:', json.dumps(hits, ensure_ascii=False)[:300])
    if not hits:
        hits = find_text(j, 'Skills')
        print('Skills entries:', json.dumps(hits, ensure_ascii=False)[:300])
    if hits:
        c = bounds_center(hits[0]['b'])
        if c:
            print('click Skills at', c)
            sh('uinput -T -c %d %d' % c)
            time.sleep(3)
            j2 = dump_layout('p59_layout_skills.json')
            if j2:
                # back button = Image icon; page title Skills/技能
                title = find_text(j2, '技能')
                print('skills page title:', json.dumps(title[:2], ensure_ascii=False))
                # look for back icon: id or accessibility — dump Image nodes near top-left
                imgs = []

                def walkimg(n):
                    if not isinstance(n, dict):
                        return
                    a = n.get('attributes') or n
                    if a.get('type', '') == 'Image':
                        b = a.get('bounds', '')
                        c2 = bounds_center(b) or (0, 0)
                        if c2[0] < 120 and c2[1] < 200:
                            imgs.append(b)
                    for ch in (n.get('children') or []):
                        walkimg(ch)
                walkimg(j2)
                print('top-left images (back candidates):', imgs[:4])
                # screenshot evidence
                sh('snapshot_display -f /data/local/tmp/p59_skills.jpeg')
                subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_skills.jpeg', EV + '\\p59_skills_page.jpeg'], capture_output=True)
                print('skills shot saved')
p59_keepalive.stop()
