import subprocess, sys, time
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\attic"


def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or '') + (r.stderr or '')).strip()


sh('uitest dumpLayout -p /data/local/tmp/z.json')
sh('snapshot_display -f /data/local/tmp/z.jpeg')
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.json', EV + r'\trial.json'], capture_output=True, timeout=60)
subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/local/tmp/z.jpeg', EV + r'\trial.jpeg'], capture_output=True, timeout=60)
from PIL import Image
im = Image.open(EV + r'\trial.jpeg').convert('L')
for name, box in [('favicon(rawfile)', (226, 187, 238, 199)), ('toolbar1($r?)', (427, 183, 447, 203)),
                  ('toolbar2', (463, 183, 483, 203)), ('toolbar3', (499, 183, 519, 203)),
                  ('bottom_plus($r)', (227, 642, 243, 658)), ('bottom_search', (259, 642, 275, 658))]:
    px = list(im.crop(box).getdata())
    bg = max(set(px), key=px.count)
    nonbg = sum(1 for v in px if abs(v - bg) > 25)
    print('%-18s %s non-bg %.1f%%' % (name, box, 100.0 * nonbg / len(px)))
