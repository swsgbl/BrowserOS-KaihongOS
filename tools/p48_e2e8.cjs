const { execSync } = require('child_process')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 })
const dump = (local) => {
  run('uitest dumpLayout -p /data/local/tmp/p48_d.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p48_d.json ${local}`, { encoding: 'utf8' })
  return JSON.parse(require('fs').readFileSync(local, 'utf8'))
}
const textsOf = (j) => { const t = []; (function w(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); if (n.children) n.children.forEach(w) })(j); return t }
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
;(async () => {
  run('aa start -a EntryAbility -b com.browseros.kaihong')
  await sleep(2000)
  run('uitest uiInput click 1254 61')   // open ⋮ menu
  await sleep(600)
  // 扫描菜单列：点击不同 y 看哪个打开设置。先 dump 结构找 Stack 浮层 bounds
  const j = dump('.verify/p48_y_m.json')
  // 找包含 Exit 的父容器 bounds
  let exitB = null, stackB = null;
  (function w(n) {
    const a = n.attributes || {}
    if (a.text === 'Exit') exitB = a.bounds
    if (n.children) n.children.forEach(w)
  })(j)
  console.log('Exit at:', exitB)
  // 菜单列扫描：x=1150, y 从 90 到 700 每 40px 试探会误触，改为读容器
  // 找 y<160 的所有 Stack/Column 容器
  let conts = [];
  (function w(n) {
    const a = n.attributes || {}
    const m = (a.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
    if (m && parseInt(m[1]) > 1000 && parseInt(m[2]) < 130 && parseInt(m[4]) > 140 && (parseInt(m[4]) - parseInt(m[2])) > 30) {
      conts.push(a.bounds + ' type=' + (n.type || '?'))
    }
    if (n.children) n.children.forEach(w)
  })(j)
  console.log('menu containers:', conts.join(' | ') || 'none')
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
