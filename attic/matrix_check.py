import csv, sys
from collections import Counter
sys.stdout.reconfigure(encoding='utf-8')
reader = csv.DictReader(open(r'D:\BrowserOS - KaihongOS\attic\optpkg\02_差距矩阵_详细核对项.csv', encoding='utf-8-sig'))
items = list(reader)
print('total:', len(items))
statuses = Counter(item.get('当前判定', '?').strip() for item in items)
for s, c in statuses.most_common():
    print('  %s: %d' % (s, c))
print('\n=== P0 items ===')
for item in items:
    if 'P0' in item.get('优先级', ''):
        print('  %s: %s | %s' % (item.get('ID', '?'), item.get('核对项', '?')[:55], item.get('当前判定', '?')[:25]))
print('\n=== P1 not implemented/stub ===')
for item in items:
    p = item.get('优先级', '')
    s = item.get('当前判定', '')
    if 'P1' in p and ('缺失' in s or '桩' in s or '未实现' in s):
        print('  %s: %s | %s' % (item.get('ID', '?'), item.get('核对项', '?')[:55], s[:25]))
