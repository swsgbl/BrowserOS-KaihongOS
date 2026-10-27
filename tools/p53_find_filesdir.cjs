const { execFileSync } = require('child_process')
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe'
const T = '192.168.161.137:10178'
// 查 app 进程真实 filesDir: 通过 /proc/<pid>/cwd 或 hilog 打印。先拿 pid
const pidOut = execFileSync(HDC, ['-t', T, 'shell', 'pidof com.browseros.kaihong'], { encoding: 'utf8' })
const pid = (pidOut || '').trim().split(/\s+/)[0]
console.log('pid:', pid)
if (!pid) process.exit(1)
// /proc/pid/cwd -> 通常是 / (app 进程)。看 fd 打开的文件路径
const maps = execFileSync(HDC, ['-t', T, 'shell', 'readlink /proc/' + pid + '/cwd'], { encoding: 'utf8' })
console.log('cwd:', maps.trim())
// 直接列 el2 下所有 browseros 目录
const dirs = execFileSync(HDC, ['-t', T, 'shell', 'find /data/app/el2 -maxdepth 4 -type d -name "*browseros*" 2>/dev/null'], { encoding: 'utf8' })
console.log('el2 dirs:\n' + dirs.trim())
// 各候选 files 下是否有既有文件（PrefsStore 写过 login_state，说明真 filesDir 有内容）
const probe = execFileSync(HDC, ['-t', T, 'shell', 'for d in $(find /data/app/el2 -maxdepth 4 -type d -name files -path "*browseros*" 2>/dev/null); do echo "== $d"; ls $d 2>/dev/null; done'], { encoding: 'utf8' })
console.log('files probes:\n' + probe.trim().substring(0, 1500))
