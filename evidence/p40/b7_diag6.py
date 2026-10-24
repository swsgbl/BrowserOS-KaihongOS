"""P40-B diag6: is the freshly-installed device abc NOW carrying the literal?
If yes -> runtime serialization drops it; if no -> install pipeline stale."""
import subprocess, sys, zipfile
sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "192.168.161.137:10178"
EV = r"D:\BrowserOS - KaihongOS\evidence\p40"
r = subprocess.run([HDC, '-t', T, 'file', 'recv', '/data/app/el1/bundle/public/com.browseros.kaihong/entry.hap',
                    EV + r'\b7_device_hap2.hap'], capture_output=True, text=True, timeout=180, encoding='utf-8', errors='replace')
print('recv:', (r.stdout or r.stderr).strip())
z = zipfile.ZipFile(EV + r'\b7_device_hap2.hap')
abc = z.read('ets/modules.abc')
print('device abc size:', len(abc))
print('has literal:', b'Preserve useful pages' in abc)
print('has MCP_INSTRUCTIONS:', b'MCP_INSTRUCTIONS' in abc)
