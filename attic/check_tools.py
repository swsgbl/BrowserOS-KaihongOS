import json, sys
sys.stdout.reconfigure(encoding='utf-8')
data = json.load(open(r'D:\BrowserOS - KaihongOS\attic\tools_check.json', encoding='utf-8'))
tools = data.get('result', {}).get('tools', [])
names = [t.get('name', '?') for t in tools]
print('tools count:', len(names))
print('names:', names)
print('evaluate_in_page:', 'evaluate_in_page' in names)
print('evaluate (alias):', 'evaluate' in names)
