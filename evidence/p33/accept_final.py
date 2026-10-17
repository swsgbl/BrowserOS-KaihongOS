"""Final acceptance visual/chat-mode round on merged P33+P34 build."""
import json, re, subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p33"


def sh(cmd, timeout=90):
    r = subprocess.run([HDC, '-t', T, 'shell', cmd], capture_output=True, text=True, timeout=timeout)
    return ((r.stdout or '') + (r.stderr or '')).strip()


def recv(remote, local):
    subprocess.run([HDC, '-t', T, 'file', 'recv', remote, EV + '\\' + local],
                   capture_output=True, text=True, timeout=60)


def dump(name):
    sh('uitest dumpLayout -p /data/local/tmp/z.json')
    recv('/data/local/tmp/z.json', name)
    return open(EV + '\\' + name, encoding='utf-8', errors='replace').read()


def shot(name):
    sh('snapshot_display -f /data/local/tmp/z.jpeg')
    recv('/data/local/tmp/z.jpeg', name)


def walk(n):
    if isinstance(n, dict):
        a = n.get('attributes')
        if isinstance(a, dict):
            yield a
        for c in (n.get('children') or []):
            yield from walk(c)
    elif isinstance(n, list):
        for c in n:
            yield from walk(c)


def find(lay, needle, exact=False):
    try:
        data = json.loads(lay)
    except json.JSONDecodeError:
        return None
    for a in walk(data):
        t = a.get('text') or ''
        if (exact and t == needle) or (not exact and needle in t):
            b = str(a.get('bounds', ''))
            if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', b):
                return b
    return None


def click(b):
    xs = [int(v) for v in re.findall(r'\d+', b)]
    sh('uitest uiInput click %d %d' % ((xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2))


print('== 1. cold start -> dashboard: hero + banner')
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
lay = dump('acc_dash.json')
shot('acc_dash.jpeg')
for probe, exact in [('What are your agents', False), ('working on', False), ('right now?', False),
                     ('Ultrafast', False), ('10× fewer tokens', False), ('Request early access', False),
                     ('BrowserOS neo', False)]:
    print('  hero/banner %-22s: %s' % (probe, find(lay, probe, exact=exact) is not None))

print('== 2. Skills page via menu')
lay = dump('acc_menu.json')
b = find(lay, '⋮') or None
# find toolbar rightmost button again
best, mb = -1, None
try:
    data = json.loads(lay)
    for a in walk(data):
        if a.get('type') != 'Button':
            continue
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', str(a.get('bounds', '')))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if y1 < 60 or y1 > 400 or x1 < 1000 or 'Enhance' in str(a.get('id', '')):
            continue
        if x2 > best:
            best, mb = x2, m.groups()
except Exception:
    pass
if mb:
    click(''.join('[%s,%s][%s,%s]' % mb))
    time.sleep(2)
    lay = dump('acc_menu2.json')
sb = find(lay, 'Skills', exact=True)
print('  menu Skills item:', sb)
if sb:
    click(sb)
    time.sleep(2.5)
    lay = dump('acc_skills.json')
    shot('acc_skills.jpeg')
    for probe in ['Skills', 'New skill', '/summarize-page', 'Runs', 'Tokens saved']:
        print('  skills page %-16s: %s' % (probe, find(lay, probe) is not None))

print('== 3. chat mode E2E (sidepanel)')
# back to shell, cold start resets; open sidepanel via toolbar agent button (btn index?)
sh('aa force-stop com.browseros.kaihong')
time.sleep(1)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
time.sleep(6)
lay = dump('acc_sp0.json')
# sidepanel toggle = toolbar Button with a11y? find via Chat Mode ON pill after opening; first open panel:
# toolbar buttons list rightmost few; the agent-panel toggle is one of them - use dump texts after each try
cands = []
try:
    data = json.loads(lay)
    for a in walk(data):
        if a.get('type') != 'Button':
            continue
        m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', str(a.get('bounds', '')))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if 60 <= y1 <= 400 and x1 > 1100 and 'Enhance' not in str(a.get('id', '')):
            cands.append((x1, ''.join('[%d,%d][%d,%d]' % (x1, y1, x2, y2))))
except Exception:
    pass
cands.sort()
print('  toolbar buttons x:', [c[0] for c in cands])
opened = False
for x1, bstr in reversed(cands):
    click(bstr)
    time.sleep(1.5)
    l2 = dump('acc_sp1.json')
    if find(l2, 'Mode ON'):
        opened = True
        print('  sidepanel opened via button x=%d' % x1)
        break
if not opened:
    print('  SIDE PANEL NOT FOUND via toolbar buttons')
    sys.exit(0)
lay = dump('acc_sp1.json')
mb2 = find(lay, 'Agent Mode ON') or find(lay, 'Chat Mode ON')
print('  mode pill:', mb2)
if mb2:
    click(mb2)
    time.sleep(1.2)
    lay = dump('acc_sp2.json')
    print('  after toggle Chat Mode ON:', find(lay, 'Chat Mode ON') is not None)
    # find input + type
    ih = None
    try:
        data = json.loads(lay)
        for a in walk(data):
            if a.get('type') == 'TextInput' and '任务' in str(a.get('hint', '')) or (a.get('type') == 'TextInput' and '问' in str(a.get('hint', ''))):
                b = str(a.get('bounds', ''))
                if re.match(r'^\[\d+,\d+\]\[\d+,\d+\]$', b):
                    ih = b
                    break
    except Exception:
        pass
    if not ih:
        try:
            for a in walk(data):
                if a.get('type') == 'TextInput':
                    b = str(a.get('bounds', ''))
                    m = re.match(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$', b)
                    if m and int(m.group(1)) > 900:  # sidepanel is right docked
                        ih = b
                        break
        except Exception:
            pass
    print('  sidepanel input:', ih)
    if ih:
        xs = [int(v) for v in re.findall(r'\d+', ih)]
        cx, cy = (xs[0] + xs[2]) // 2, (xs[1] + xs[3]) // 2
        sh('uitest uiInput inputText %d %d %s' % (cx, cy, "'你好，一句话介绍你自己'"))
        time.sleep(1)
        lay = dump('acc_sp3.json')
        sb2 = find(lay, '发送', exact=True)
        print('  发送 button:', sb2)
        if sb2:
            click(sb2)
            print('  sent; polling for chat answer (single-shot LLM)...')
            ok = False
            for i in range(10):
                time.sleep(6)
                out = sh('hilog -x | grep -E "P33" | tail -6')
                if 'chat mode reply' in out or 'single' in out.lower():
                    print('  HILOG:', out.replace('\n', ' | ')[:300])
                    ok = True
                    break
            lay = dump('acc_sp4.json')
            shot('acc_chat.jpeg')
            print('  chat bubble page dumped; mode pill still:', find(lay, 'Mode ON'))
print('DONE')
