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
            res.append((t[:34], a.get('bounds', '')))
        for c in (n.get('children') or []):
            w(c)
    w(root)
    return res


# close any open panels: press ESC twice
sh('uitest uiInput keyEvent Escape')
time.sleep(0.8)
sh('uitest uiInput keyEvent Escape')
time.sleep(0.8)

# 1) focus omnibox
sh('uinput -T -c 711 161')
time.sleep(1.2)
# 2) select-all + clear
sh('uitest uiInput keyEvent Ctrl+A')
time.sleep(0.4)
# 3) switch IME to EN: click the '中' indicator in system tray? The IME toggle is inside the browser toolbar too ('中' at right).
# find '中' bounds
j = dump('p59_l_ime.json')
zh = find(j, '中') if j else []
if zh:
    mm = re.findall(r'\d+', zh[0][1])
    cx, cy = (int(mm[0]) + int(mm[2])) // 2, (int(mm[1]) + int(mm[3])) // 2
    print('toggling IME at', cx, cy)
    sh('uinput -T -c %d %d' % (cx, cy))
    time.sleep(1.5)

# 4) type URL (IME now EN hopefully)
sh("uitest uiInput text 'browseros://skills'")
time.sleep(1)
sh('uitest uiInput keyEvent Enter')
time.sleep(3.5)

j = dump('p59_l_sk5.json')
if j:
    hits = find(j, '技能') or find(j, 'Skills') or find(j, 'skill')
    print('SKILLS PAGE HITS:', json.dumps(hits[:5], ensure_ascii=False))
    sh('snapshot_display -f /data/local/tmp/p59_sk5.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_sk5.jpeg', EV + '\\p59_skills5.jpeg'], capture_output=True)
