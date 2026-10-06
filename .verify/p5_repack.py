import json, zipfile, os, shutil

src_hap = r'D:\BrowserOS - KaihongOS\entry\build\default\outputs\default\entry-default-unsigned.hap'
work_dir = r'D:\BrowserOS - KaihongOS\.verify\p4_repack'
extract_dir = os.path.join(work_dir, 'hap-extracted')

if os.path.exists(extract_dir):
    shutil.rmtree(extract_dir)
os.makedirs(extract_dir, exist_ok=True)

with zipfile.ZipFile(src_hap, 'r') as zf:
    zf.extractall(extract_dir)

# module.json
mj_path = os.path.join(extract_dir, 'module.json')
with open(mj_path, 'r', encoding='utf-8') as f:
    module_json = json.load(f)
module_json['app']['minAPIVersion'] = 14
module_json['app']['targetAPIVersion'] = 14
module_json['app']['compileSdkVersion'] = '14'
module_json['app']['compileSdkType'] = 'OpenHarmony'
with open(mj_path, 'w', encoding='utf-8') as f:
    json.dump(module_json, f, ensure_ascii=False)

# pack.info
pi_path = os.path.join(extract_dir, 'pack.info')
with open(pi_path, 'r', encoding='utf-8') as f:
    pack_info = json.load(f)
pack_info['summary']['modules'][0]['apiVersion']['compatible'] = 14
pack_info['summary']['modules'][0]['apiVersion']['target'] = 14
with open(pi_path, 'w', encoding='utf-8') as f:
    json.dump(pack_info, f, ensure_ascii=False)

# Repack
hap_path = os.path.join(work_dir, 'entry-p4-api14.hap')
with zipfile.ZipFile(hap_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(extract_dir):
        for file in files:
            file_path = os.path.join(root, file)
            arcname = os.path.relpath(file_path, extract_dir)
            zf.write(file_path, arcname)

print('HAP repacked:', hap_path)
print('Size:', os.path.getsize(hap_path), 'bytes')
with zipfile.ZipFile(hap_path, 'r') as zf:
    with zf.open('module.json') as f:
        verify = json.load(f)
        print('minAPIVersion:', verify['app']['minAPIVersion'], 'targetAPIVersion:', verify['app']['targetAPIVersion'], 'compileSdkVersion:', verify['app']['compileSdkVersion'])
