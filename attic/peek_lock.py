import re, sys
sys.stdout.reconfigure(encoding='utf-8')
lay = open(r'D:\BrowserOS - KaihongOS\attic\lock_check.json', encoding='utf-8', errors='replace').read()
print('len:', len(lay))
texts = [t for t in re.findall(r'"text":"([^"]{1,18})"', lay) if t]
print('TEXTS:', texts[:12])
print('BrowserOS icon:', 'BrowserOS' in lay)
