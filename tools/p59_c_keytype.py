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


def omnibox_text(j):
    res = []

    def w(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or n
        if (a.get('id', '') or '') == 'p11f_omnibox':
            res.append(a.get('text', ''))
        for c in (n.get('children') or []):
            w(c)
    w(j)
    return res


# 1) focus omnibox + select all
sh('uinput -T -c 711 161')
time.sleep(1)
sh('uitest uiInput keyEvent Ctrl+A')
time.sleep(0.5)

# 2) type letters one by one (bypasses IME composition)
url = 'browseros://skills'
for ch in url:
    if ch == ':':
        sh('uitest uiInput keyEvent Shift+Semicolon')
    elif ch == '/':
        sh('uitest uiInput keyEvent Slash')
    else:
        sh("uitest uiInput keyEvent %s" % ch.upper())
    time.sleep(0.12)
time.sleep(0.8)
sh('uitest uiInput keyEvent Enter')
time.sleep(4)

j = dump('p59_l_sk6.json')
if j:
    print('omnibox now:', omnibox_text(j))
    hits = []

    def w2(n):
        if not isinstance(n, dict):
            return
        a = n.get('attributes') or n
        t = a.get('text', '') or ''
        if 'Skills' in t or '技能' in t or 'New skill' in t:
            hits.append((t[:30], a.get('bounds', '')))
        for c in (n.get('children') or []):
            w2(c)
    w2(j)
    print('SKILLS HITS:', json.dumps(hits[:5], ensure_ascii=False))
    sh('snapshot_display -f /data/local/tmp/p59_sk6.jpeg')
    subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/p59_sk6.jpeg', EV + '\\p59_skills6.jpeg'], capture_output=True)
