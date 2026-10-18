import json, re, sys
sys.stdout.reconfigure(encoding='utf-8')
for name in ('a2_w3.json', 'a2_w4.json'):
    lay = open(r'D:\BrowserOS - KaihongOS\evidence\p35' + '\\' + name, encoding='utf-8', errors='replace').read()
    texts = re.findall(r'"text":"([^"]{1,40})"', lay)
    print(name, [t for t in texts if t][:16])
    # TextInput 值
    m = re.findall(r'"text":"([^"]*)","[^"]*":"[^"]*","type":"TextInput"', lay)
    try:
        data = json.loads(lay)
    except Exception:
        data = None
    if data:
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
        for a in walk(data):
            if a.get('type') == 'TextInput':
                print('  INPUT text=', repr(a.get('text')), 'bounds=', a.get('bounds'))
