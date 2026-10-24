"""P40-A: reproduce exact V1-style entry ORDER (abc first, index in order list) with STORED entries,
keeping V2 index (API23 device accepts RestoolV2 6.1.0.0 - dshapp proves it).
Difference vs P39 build_api23_hap.py: compression STORED + original entry order preserved."""
import json, os, shutil, zipfile
sys = __import__('sys'); sys.stdout.reconfigure(encoding='utf-8')
PROJ = r"D:\BrowserOS - KaihongOS"
SRC_HAP = os.path.join(PROJ, "entry", "build", "default", "outputs", "default", "entry-default-unsigned.hap")
OUT_HAP = os.path.join(PROJ, "entry-api23-stored-unsigned.hap")
API = 23

zsrc = zipfile.ZipFile(SRC_HAP)
names = zsrc.namelist()
# patch module.json + pack.info contents only
mj = json.loads(zsrc.read('module.json'))
mj['app']['minAPIVersion'] = API
mj['app']['targetAPIVersion'] = API
mj['app']['compileSdkVersion'] = '6.0.0'
mj['app']['compileSdkType'] = 'HarmonyOS'
pi = json.loads(zsrc.read('pack.info'))
pi['summary']['modules'][0]['apiVersion']['compatible'] = API
pi['summary']['modules'][0]['apiVersion']['target'] = API

# patch inside zip: write everything STORED, same order
with zipfile.ZipFile(OUT_HAP, 'w') as zf:
    for n in names:
        if n == 'module.json':
            data = json.dumps(mj, indent=2, ensure_ascii=False).encode('utf-8')
        elif n == 'pack.info':
            data = json.dumps(pi, indent=2, ensure_ascii=False).encode('utf-8')
        else:
            data = zsrc.read(n)
        zi = zipfile.ZipInfo(n, date_time=(2026, 1, 1, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_STORED
        zi.external_attr = 0o644 << 16
        zf.writestr(zi, data)

# verify
z = zipfile.ZipFile(OUT_HAP)
print('OUT:', OUT_HAP, os.path.getsize(OUT_HAP), 'B')
print('entries:', len(z.namelist()))
print('index head:', z.read('resources.index')[:17])
allstored = all(zi.compress_type == 0 for zi in z.infolist())
print('all STORED:', allstored)
print('first 6:', z.namelist()[:6])
mj2 = json.loads(z.read('module.json'))
print('minAPI:', mj2['app']['minAPIVersion'], 'target:', mj2['app']['targetAPIVersion'])
