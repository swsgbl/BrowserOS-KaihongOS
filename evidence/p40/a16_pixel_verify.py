"""P40-A: pixel-verify icons on the STORED build screenshot (reuse P39 probe boxes)."""
import sys
sys.stdout.reconfigure(encoding='utf-8')
from PIL import Image

EV = r"D:\BrowserOS - KaihongOS\evidence\p40"
im = Image.open(EV + r'\a15_stored.jpeg').convert('L')
print('shot size:', im.size)
# P39 probe boxes (same layout): favicon rawfile + toolbar icons + bottom icons
for name, box in [('favicon(rawfile)', (226, 187, 238, 199)), ('toolbar1', (427, 183, 447, 203)),
                  ('toolbar2', (463, 183, 483, 203)), ('toolbar3', (499, 183, 519, 203)),
                  ('bottom_plus', (227, 642, 243, 658)), ('bottom_search', (259, 642, 275, 658))]:
    px = list(im.crop(box).getdata())
    bg = max(set(px), key=px.count)
    nonbg = sum(1 for v in px if abs(v - bg) > 25)
    print('%-18s %s non-bg %.1f%%' % (name, box, 100.0 * nonbg / len(px)))
# whole-window non-bg ratio (P38 smoke gate: >=37%)
g = im.convert('L')
w, h = g.size
win = g.crop((0, 40, w, 760))
px = list(win.getdata())
bg = max(set(px), key=px.count)
nonbg = sum(1 for v in px if abs(v - bg) > 25)
print('window non-bg: %.1f%%' % (100.0 * nonbg / len(px)))
