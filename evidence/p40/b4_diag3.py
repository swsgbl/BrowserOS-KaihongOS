"""P40-B diag3: is the on-device abc stale? grep instructions in installed hap abc."""
import subprocess, sys, zipfile
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p40"

r = subprocess.run([HDC, '-t', T, 'file', 'recv',
                    '/data/app/el1/bundle/public/com.browseros.kaihong/entry.hap',
                    EV + r'\b3_device_hap.zip.hap'], capture_output=True, text=True, timeout=180, encoding='utf-8', errors='replace')
print('recv:', (r.stdout or r.stderr).strip())
z = zipfile.ZipFile(EV + r'\b3_device_hap.zip.hap')
abc = z.read('ets/modules.abc')
print('abc size:', len(abc))
print('has MCP_INSTRUCTIONS literal:', b'Preserve useful pages' in abc)
print('has instructions key:', b'instructions' in abc)
# also our locally-built one
z2 = zipfile.ZipFile(r"D:\BrowserOS - KaihongOS\entry-api23-unsigned.hap")
abc2 = z2.read('ets/modules.abc')
print('local abc has literal:', b'Preserve useful pages' in abc2)
print('local abc has instructions key:', b'instructions' in abc2)
