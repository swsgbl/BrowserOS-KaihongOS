"""P40-A: compress-type forensics — hvigor original vs our api23 repack vs device dshapp."""
import sys, zipfile
sys.stdout.reconfigure(encoding='utf-8')
EV = r"D:\BrowserOS - KaihongOS\evidence\p40"
HVIGOR = r"D:\BrowserOS - KaihongOS\entry\build\default\outputs\default\entry-default-unsigned.hap"
API23 = EV + r"\device_entry.hap"   # what's on device (built by build_api23_hap.py)
DSH = EV + r"\dshapp.hap"

for tag, path in [('HVIGOR-ORIG', HVIGOR), ('OURS-ON-DEVICE', API23), ('DSHAPP', DSH)]:
    try:
        z = zipfile.ZipFile(path)
        print('===', tag)
        for n in z.namelist():
            if n.endswith(('resources.index', 'module.json', 'pack.info')) or '/rawfile/' in n or '/media/' in n or '/element/' in n or n.startswith('ets/'):
                zi = z.getinfo(n)
                ct = 'STORED' if zi.compress_type == 0 else 'DEFLATE'
                print('  %-8s %8d  %s' % (ct, zi.file_size, n))
    except Exception as e:
        print(tag, 'ERR', e)
