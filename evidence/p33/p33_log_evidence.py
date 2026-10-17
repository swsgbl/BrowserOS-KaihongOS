"""P33 A/B/C 日志证据版:不依赖 UI 前台(避开并行会话干扰)
- A: hilog 'selection captured' + '[BCP][P33] selection capture installed'
- B: hilog 'chat mode toggled/saved/loaded'
- C: hilog 'tab auto-attached'
"""
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p33"

r = subprocess.run([HDC, "-t", T, "shell", "hilog -x"], capture_output=True, text=True, timeout=60)
out = ((r.stdout or "") + (r.stderr or ""))
open(EV + r"\abc_hilog_evidence.txt", "w", encoding="utf-8").write(out)

checks = {
    'A 注入安装': '[BCP][P33] selection capture installed',
    'A 选区捕获': 'selection captured',
    'A chip 丢弃': 'selection chip dismissed',
    'B 模式切换': 'chat mode toggled',
    'B 模式保存': 'chat mode saved',
    'B 模式载入': 'chat mode loaded',
    'C tab 附加': 'tab auto-attached',
    'C tab 移除': 'attached tab removed',
}
print('== hilog 证据(P33 相关)')
for name, needle in checks.items():
    hits = [l.split('JSAPP: ')[-1] if 'JSAPP: ' in l else l for l in out.splitlines() if needle in l]
    print('%-10s: %s' % (name, hits[-1] if hits else '未见'))
