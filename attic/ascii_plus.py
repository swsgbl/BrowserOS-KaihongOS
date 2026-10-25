from PIL import Image
import sys
sys.stdout.reconfigure(encoding='utf-8')
img = Image.open(r'D:\BrowserOS - KaihongOS\evidence\p45\center_check.jpeg').convert('L')
print('screenshot size:', img.size)

# Find the tab strip area (left side of app window)
# The app window in ContainerModal starts around x=200-300
# Tab strip is the leftmost ~80px of the window

# First, find the app window by looking for the omnibox or content
# Let's crop the full left half and render at higher resolution
crop = img.crop((200, 100, 450, 400))
crop = crop.resize((50, 30))
px = crop.load()
ramp = ' .:-=+*#%@'
for y in range(30):
    print(''.join(ramp[min(9, (255 - px[x, y]) * 10 // 256)] for x in range(50)))

# Now zoom into the area right below the last tab
# Look for the + icon pattern
print('\n=== Zoom below last tab area ===')
# Try different y ranges to find the + button
for y_start in range(150, 250, 25):
    crop2 = img.crop((250, y_start, 400, y_start + 40))
    crop2 = crop2.resize((40, 10))
    px2 = crop2.load()
    line = ''
    for yy in range(10):
        row = ''.join(ramp[min(9, (255 - px2[x, yy]) * 10 // 256)] for x in range(40))
        if any(c != ' ' and c != '.' for c in row):
            line += row + '\n'
    if line:
        print('y=%d-%d:' % (y_start, y_start + 40))
        print(line)
