"""P40-A: pull device haps + compare zip entries (ours vs system dshapp)."""
import subprocess, sys, zipfile
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p40"

def sh(c, tmo=90):
    r = subprocess.run([HDC, '-t', T, 'shell', c], capture_output=True, text=True, timeout=tmo, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

def recv(remote, local):
    r = subprocess.run([HDC, '-t', T, 'file', 'recv', remote, local], capture_output=True, text=True, timeout=180, encoding='utf-8', errors='replace')
    return ((r.stdout or '') + (r.stderr or '')).strip()

print('--- dshapp hap path')
dsh = sh('find /data/app/el1/bundle/public/com.example.dshapp -name "*.hap" 2>/dev/null | head -n1')
print(dsh)
print(recv(dsh, EV + r'\dshapp.hap'))
print(recv('/data/app/el1/bundle/public/com.browseros.kaihong/entry.hap', EV + r'\device_entry.hap'))

for tag, path in [('OURS', EV + r'\device_entry.hap'), ('DSHAPP', EV + r'\dshapp.hap')]:
    try:
        z = zipfile.ZipFile(path)
        names = z.namelist()
        print('===', tag, len(names), 'entries')
        rf = [n for n in names if 'rawfile' in n]
        print('  rawfile entries:', len(rf), rf[:5])
        idx = z.read('resources.index')
        print('  index head:', idx[:17])
        # how entries are compressed
        infos = {n: (z.getinfo(n).compress_type, z.getinfo(n).file_size) for n in names[:3]}
        print('  first entries:', infos)
        print('  has ets/modules.abc:', 'ets/modules.abc' in names)
    except Exception as e:
        print(tag, 'ERR', e)
