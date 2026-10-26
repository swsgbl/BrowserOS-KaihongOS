// P49 侦查：点击 1254,61 后浮层只显示"退出"——完整菜单是否需要滚动？或菜单是 hover 展开？
// 尝试:1) 点开菜单 2) dump 3) 向上滚浮层 4) dump 再看
const { execSync } = require('child_process')
const fs = require('fs')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 })
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
const dump = (local) => {
  run('uitest dumpLayout -p /data/local/tmp/p49_x.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p49_x.json ${local}`, { encoding: 'utf8' })
  return JSON.parse(fs.readFileSync(local, 'utf8'))
}
const band = (j) => {
  const out = [];
  (function w(n) {
    const a = n.attributes || {}
    const m = (a.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
    if (m && parseInt(m[1]) > 1000 && parseInt(m[2]) > 70 && parseInt(m[4]) < 400 && typeof a.text === 'string' && a.text) out.push(a.text + ' ' + a.bounds)
    if (n.children) n.children.forEach(w)
  })(j)
  return out
}
;(async () => {
  run('aa force-stop com.browseros.kaihong'); await sleep(500)
  run('aa start -a EntryAbility -b com.browseros.kaihong'); await sleep(3000)
  run('uitest uiInput click 1254 61')
  await sleep(1200)
  let j = dump('.verify/p49_probe_a.json')
  console.log('T0 menu band:', band(j).join(' | ') || '(empty)')
  // 滚动浮层
  run('uitest uiInput swipe 1150 150 1150 400')
  await sleep(800)
  j = dump('.verify/p49_probe_b.json')
  console.log('T1 after scroll:', band(j).join(' | ') || '(empty)')
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
