"""P33 主动日志验证:驱动一次真实交互序列,只靠 hilog 判定(不受前台页面影响)
序列: 拉起应用→点书签开网页→等加载→双击选词→(轮询会捕获)→开侧栏→看 auto-attached
"""
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding='utf-8')
HDC = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
T = "127.0.0.1:15566"
EV = r"D:\BrowserOS - KaihongOS\evidence\p33"


def sh(cmd, tmo=30):
    r = subprocess.run([HDC, "-t", T, "shell", cmd], capture_output=True, text=True, timeout=tmo)
    return ((r.stdout or "") + (r.stderr or "")).strip()


def hilog_lines():
    out = sh("hilog -x", tmo=60)
    open(EV + r"\driven_hilog.txt", "w", encoding="utf-8").write(out)
    return out


print('== 清理日志缓冲')
sh("hilog -r")

print('== 冷启动应用')
sh("aa force-stop com.browseros.kaihong")
time.sleep(1.5)
sh("aa start -a EntryAbility -b com.browseros.kaihong")
time.sleep(5)

print('== 恢复会话 tabs(等 restore) 后双击网页选词')
time.sleep(3)
# 网页 tab 若恢复了 example.com,页面中心双击选中词
subprocess.run([HDC, "-t", T, "shell", "uitest uiInput click 700 480"], capture_output=True, timeout=25)
time.sleep(0.2)
subprocess.run([HDC, "-t", T, "shell", "uitest uiInput click 700 480"], capture_output=True, timeout=25)
print('   已双击')
time.sleep(4)

out = hilog_lines()
for needle, name in [
    ('selection captured', 'A 选区捕获'),
    ('auto-attached', 'C tab 附加'),
    ('chat mode', 'B 模式'),
]:
    hits = [l for l in out.splitlines() if needle in l]
    print('%-12s: %s' % (name, hits[-1].split('JSAPP: ')[-1] if 'JSAPP: ' in (hits[-1] if hits else '') else (hits[-1] if hits else '未见')))
