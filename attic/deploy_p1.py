import json, zipfile, os, subprocess, shutil, sys

WORK_DIR = r'D:\BrowserOS - KaihongOS'
HDC = r'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
HAP_SOURCE = os.path.join(WORK_DIR, 'entry', 'build', 'default', 'outputs', 'default', 'entry-default-unsigned.hap')
DEPLOY_DIR = os.path.join(WORK_DIR, 'entry', 'build', 'default', 'outputs', 'default', 'hap-deploy-p1')
EXTRACT_DIR = os.path.join(DEPLOY_DIR, 'hap-extracted')
HAP_OUTPUT = os.path.join(DEPLOY_DIR, 'entry-p1-api14.hap')
TARGET = '127.0.0.1:15566'

def hdc(*args, **kw):
    cmd = [HDC, '-t', TARGET] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=kw.get('timeout', 120))
    out = (r.stdout or '') + (r.stderr or '')
    return out.strip()

if os.path.exists(DEPLOY_DIR):
    shutil.rmtree(DEPLOY_DIR)
os.makedirs(DEPLOY_DIR)

# Extract HAP
with zipfile.ZipFile(HAP_SOURCE, 'r') as zf:
    zf.extractall(EXTRACT_DIR)

# Modify module.json
module_json_path = os.path.join(EXTRACT_DIR, 'module.json')
with open(module_json_path, 'r', encoding='utf-8') as f:
    module_json = json.load(f)
module_json['app']['minAPIVersion'] = 14
module_json['app']['targetAPIVersion'] = 14
module_json['app']['compileSdkVersion'] = '14'
module_json['app']['compileSdkType'] = 'OpenHarmony'
with open(module_json_path, 'w', encoding='utf-8') as f:
    json.dump(module_json, f, ensure_ascii=False)

# Modify pack.info
pack_info_path = os.path.join(EXTRACT_DIR, 'pack.info')
with open(pack_info_path, 'r', encoding='utf-8') as f:
    pack_info = json.load(f)
pack_info['summary']['modules'][0]['apiVersion']['compatible'] = 14
pack_info['summary']['modules'][0]['apiVersion']['target'] = 14
with open(pack_info_path, 'w', encoding='utf-8') as f:
    json.dump(pack_info, f, ensure_ascii=False)

# Repack HAP (module.json & pack.info stored first, STORED not required but keep deflated)
with zipfile.ZipFile(HAP_OUTPUT, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(EXTRACT_DIR):
        for file in files:
            file_path = os.path.join(root, file)
            arcname = os.path.relpath(file_path, EXTRACT_DIR).replace('\\', '/')
            zf.write(file_path, arcname)

print('HAP repacked:', HAP_OUTPUT, os.path.getsize(HAP_OUTPUT), 'bytes')

# Send
print('SEND:', hdc('file', 'send', HAP_OUTPUT, '/data/local/tmp/entry-p1-api14.hap'))

# Sign in VM
sign_cmd = ('/data/local/home/.local/bin/hap-sign-tool sign-app '
    '-keyAlias "OpenHarmony Application Release" -signAlg SHA256withECDSA -mode localSign '
    '-appCertFile /data/local/home/.ohos/signature/OpenHarmonyApplication.pem '
    '-profileFile /data/local/home/.ohos/signature/app1-profile-release.p7b '
    '-inFile /data/local/tmp/entry-p1-api14.hap '
    '-outFile /data/local/tmp/entry-p1-signed.hap '
    '-keystoreFile /data/local/home/.ohos/signature/OpenHarmony.p12 '
    '-keyPwd 123456 -keystorePwd 123456 -compatibleVersion 14')
print('SIGN:', hdc('shell', sign_cmd, timeout=180))

# Install
print('INSTALL:', hdc('shell', 'bm install -p /data/local/tmp/entry-p1-signed.hap -r'))

# Start
print('START:', hdc('shell', 'aa start -a EntryAbility -b com.browseros.kaihong'))
