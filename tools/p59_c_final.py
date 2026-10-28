import sys, time, json, re, subprocess
sys.path.insert(0, r"D:\BrowserOS - KaihongOS\tools")
from p59_mcp import sh, HDC, T

EV = r"D:\BrowserOS - KaihongOS\evidence\p59"


def dump(name):
    out = sh('uitest dumpLayout')
    m = re.search(r'saved to:(\S+)', out)
    if not m:
        return None
    subprocess.run([HDC, '-t', T, 'file', 'recv', m.group(1), EV + '\\' + name], capture_output=True)
    try:
        return json.load(open(EV + '\\' + name, encoding='utf-8'))
    except Exception:
        return None


def find(root, needle):
    res = []

    def w(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or n
        t = a.get('text', '') or ''
        if needle in t:
            res.append((t[:30], a.get('bounds', '')))
        for c in (n.get('children') or []):
            w(c)
    w(root)
    return res


# 1) omnibox -> browseros://skills
sh('uinput -T -c 711 161')
time.sleep(1.5)
# type text via uitest? No — use hdc shell "uitest uiInput" or aa input. Use paramennon: uinput supports text? No.
# Use the system IME path: uitest uiInput keyEvent? Simplest: uiInput text
sh("uitest uiInput text 'browseros://skills'")
time.sleep(1)
sh('uitest uiInput keyEvent Enter')
time.sleep(3.5)

j = dump('p59_l_skills3.json')
if j:
    hits = find(j, '技能') or find(j, 'Skills') or find(j, 'skill')
    print('skills page text hits:', json.dumps(hits[:4], ensure_ascii=False))
    sh('snapshot_display -f /data/local/tmp/p59_sk3.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_sk3.jpeg', EV + '\\p59_skills3.jpeg'], capture_output=True)
    # back icon: Image node top-left of the app window
    imgs = []

    def wi(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or n
        if a.get('type', '') == 'Image':
            bb = a.get('bounds', '')
            mm = re.findall(r'\d+', bb)
            if len(mm) >= 4:
                cx, cy = (int(mm[0]) + int(mm[2])) // 2, (int(mm[1]) + int(mm[3])) // 2
                if cx < 200 and 100 < cy < 260:
                    imgs.append((bb, cx, cy))
        for ch in (n.get('children') or []):
            wi(ch)
    wi(j)
    print('back candidates:', imgs[:4])
    if imgs:
        cx, cy = imgs[0][1], imgs[0][2]
        print('clicking back at', cx, cy)
        sh('uinput -T -c %d %d' % (cx, cy))
        time.sleep(2.5)
        j2 = dump('p59_l_afterback2.json')
        if j2:
            still = find(j2, 'Skills 台账') or find(j2, 'New skill')
            omni = find(j2, 'https://') or find(j2, 'wps.cn')
            print('after back: still-on-skills=%s, back-to-web=%s' % (bool(still), bool(omni)))
        sh('snapshot_display -f /data/local/tmp/p59_ab.jpeg')
        subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_ab.jpeg', EV + '\\p59_after_back.jpeg'], capture_output=True)
else:
    print('dump fail')
