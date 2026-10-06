import json, zipfile, os, shutil

src_hap = r'D:\BrowserOS - KaihongOS\entry\build\default\outputs\default\entry-default-unsigned.hap'
work_dir = r'D:\BrowserOS - KaihongOS\.verify\r7-repack'
extract_dir = os.path.join(work_dir, 'hap-extracted')
out_hap = r'D:\BrowserOS - KaihongOS\entry-api14-v7-unsigned.hap'

if os.path.exists(extract_dir):
    shutil.rmtree(extract_dir)
os.makedirs(extract_dir, exist_ok=True)

with zipfile.ZipFile(src_hap, 'r') as zf:
    zf.extractall(extract_dir)

# module.json -> API14
with open(os.path.join(extract_dir, 'module.json'), 'r', encoding='utf-8') as f:
    module_json = json.load(f)
module_json['app']['minAPIVersion'] = 14
module_json['app']['targetAPIVersion'] = 14
module_json['app']['compileSdkVersion'] = '14'
module_json['app']['compileSdkType'] = 'OpenHarmony'
with open(os.path.join(extract_dir, 'module.json'), 'w', encoding='utf-8') as f:
    json.dump(module_json, f, ensure_ascii=False)

# pack.info -> API14
with open(os.path.join(extract_dir, 'pack.info'), 'r', encoding='utf-8') as f:
    pack_info = json.load(f)
pack_info['summary']['modules'][0]['apiVersion']['compatible'] = 14
pack_info['summary']['modules'][0]['apiVersion']['target'] = 14
with open(os.path.join(extract_dir, 'pack.info'), 'w', encoding='utf-8') as f:
    json.dump(pack_info, f, ensure_ascii=False)

with zipfile.ZipFile(out_hap, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(extract_dir):
        for file in files:
            file_path = os.path.join(root, file)
            arcname = os.path.relpath(file_path, extract_dir).replace('\\', '/')
            zf.write(file_path, arcname)

print('HAP repacked:', out_hap)
print('Size:', os.path.getsize(out_hap), 'bytes')
with zipfile.ZipFile(out_hap, 'r') as zf:
    with zf.open('module.json') as f:
        verify = json.load(f)
        print('bundleName:', verify['app']['bundleName'])
        print('minAPIVersion:', verify['app']['minAPIVersion'])
        print('targetAPIVersion:', verify['app']['targetAPIVersion'])
        print('compileSdkVersion:', verify['app']['compileSdkVersion'])
        print('compileSdkType:', verify['app']['compileSdkType'])
