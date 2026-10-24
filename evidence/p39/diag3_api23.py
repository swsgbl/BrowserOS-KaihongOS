import json, re, sys
sys.stdout.reconfigure(encoding='utf-8')
from PIL import Image

im = Image.open(r'D:\BrowserOS - KaihongOS\attic\api23_v3.jpeg')
print('screenshot size:', im.size)
lay = open(r'D:\BrowserOS - KaihongOS\attic\api23_v3.json', encoding='utf-8', errors='replace').read()
data = json.loads(lay)
root = data['children'][0]['attributes'] if isinstance(data, dict) and data.get('children') else None
print('dump root bounds:', root.get('bounds') if root else '?')
# hero 渐变卡（蓝#2E6FE8→紫#8B5CF6）：在截图中找蓝色像素簇，对照 dump 里 hero 卡 bounds
g = im.convert('RGB')
w, h = g.size
blue_hits = []
for x in range(0, w, 10):
    for y in range(0, h, 10):
        r, gg, b = g.getpixel((x, y))
        if b > 150 and b - r > 60 and gg < 150:
            blue_hits.append((x, y))
print('blue pixels count(sampled):', len(blue_hits), 'sample:', blue_hits[:8])
# dump 里的 hero TextInput bounds（问点什么 placeholder）
i = lay.find('问点什么')
if i >= 0:
    seg = lay[max(0, i - 500):i]
    m = re.findall(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', seg)
    print('chat input dump bounds near:', m[-1] if m else '?')
