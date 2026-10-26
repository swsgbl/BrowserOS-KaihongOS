// P50 点击器: uitest uiInput click + 截图 + 拉回
const { execSync } = require('child_process')
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe'
const T = '192.168.161.137:10178'
const PROJ = 'D:/BrowserOS - KaihongOS'

const x = process.argv[2], y = process.argv[3], shot = process.argv[4] || 'click'
function hdc(...args) {
  try { return execSync('"' + HDC + '" -t ' + T + ' ' + args.join(' '), { maxBuffer: 20e6, timeout: 30000 }).toString() }
  catch (e) { return (e.stdout || '') + (e.stderr || '') }
}
if (x && y) {
  console.log('click', hdc('shell', 'uinput', '-i', '/dev/input/event1', 'tap', x, y).trim().slice(0, 80))
}
if (shot !== 'noclick') {
  // 等待 UI 稳定
  require('child_process').execSync('ping -n 2 127.0.0.1 >nul')
  hdc('shell', 'snapshot_display', '-f', '/data/local/tmp/p50_shot.jpeg')
  hdc('file', 'recv', '/data/local/tmp/p50_shot.jpeg', PROJ + '/evidence/p50/' + shot + '.jpeg')
  console.log('shot saved:', shot + '.jpeg')
}
