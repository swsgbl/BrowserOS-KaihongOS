"""P40-B diag4: diff device abc vs local abc — find why device lacks instructions."""
import sys, zipfile
sys.stdout.reconfigure(encoding='utf-8')
EV = r"D:\BrowserOS - KaihongOS\evidence\p40"
a = zipfile.ZipFile(EV + r'\b3_device_hap.zip.hap').read('ets/modules.abc')
b = zipfile.ZipFile(r"D:\BrowserOS - KaihongOS\entry-api23-unsigned.hap").read('ets/modules.abc')
print('device abc:', len(a), 'local abc:', len(b))
print('device has sessionManager markers:', b'browseros-kaihong' in a)
print('local has literal:', b'Preserve useful pages' in b)
print('device has literal:', b'Preserve useful pages' in a)
# where does the instruction string sit in local abc? (string pool)
i = b.find(b'Preserve useful pages')
print('local literal offset:', i, 'context:', b[i-60:i+80])
# search for MCP_INSTRUCTIONS var name
print('local has MCP_INSTRUCTIONS name:', b'MCP_INSTRUCTIONS' in b)
print('device has MCP_INSTRUCTIONS name:', b'MCP_INSTRUCTIONS' in a)
