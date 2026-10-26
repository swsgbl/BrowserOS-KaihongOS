const { execSync } = require('child_process')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 })
// 锁屏解锁序列：wakeup → 上滑 → 再试 aa start
run('power-shell wakeup')
run('uinput -T -m 640 650 640 150 400')
setTimeout(() => {
  try {
    console.log(run('aa start -a EntryAbility -b com.browseros.kaihong'))
  } catch (e) { console.log('start1: ' + String(e.message).slice(0, 120)) }
  // 二次尝试
  setTimeout(() => {
    try {
      console.log(run('aa start -a EntryAbility -b com.browseros.kaihong'))
    } catch (e) { console.log('start2: ' + String(e.message).slice(0, 120)) }
  }, 2000)
}, 2500)
