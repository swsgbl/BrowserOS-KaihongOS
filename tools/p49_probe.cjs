const { execSync } = require('child_process')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 })
const dump = (local) => {
  run('uitest dumpLayout -p /data/local/tmp/p49_p.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p49_p.json ${local}`, { encoding: 'utf8' })
  return JSON.parse(require('fs').readFileSync(local, 'utf8'))
}
const textsOf = (j) => { const t = []; (function w(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); if (n.children) n.children.forEach(w) })(j); return t }
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
;(async () => {
  // 找 ⋮ 按钮：dump 后找 main menu 按钮坐标
  let j = dump('evidence/p49/probe0.json')
  // 找带 tbMainMenu 或 image 按钮的节点：直接打印顶层 Stack 附近右上角可点元素
  let cands = [];
  (function w(n) {
    const a = n.attributes || {}
    const m = (a.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
    if (m && parseInt(m[1]) > 1150 && parseInt(m[2]) < 110 && (parseInt(m[3]) - parseInt(m[1])) < 80 && (parseInt(m[4]) - parseInt(m[2])) < 80) {
      cands.push(a.bounds + ' type=' + (n.type || '?') + ' id=' + (a.id || '') + ' key=' + (a.key || ''))
    }
    if (n.children) n.children.forEach(w)
  })(j)
  console.log('top-right candidates:\n' + cands.join('\n'))
  await sleep(300)
  run('uitest uiInput click 1254 61')
  await sleep(1400)
  j = dump('evidence/p49/probe1.json')
  const texts = textsOf(j)
  console.log('after click, menu items:', texts.filter(t => /新建|设置|退出|技能|Skills|历史|书签/.test(t)).join(' | ') || 'NONE')
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
