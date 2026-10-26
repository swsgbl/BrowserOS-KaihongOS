const { execSync } = require('child_process')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 })
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
;(async () => {
  run('uitest uiInput keyEvent 27')  // ESC 关输入法/候选
  await sleep(500)
  // 主菜单路径：⋮ 按钮 (1254,61)，菜单项 dump 后点"设置"
  run('uitest uiInput click 1254 61')
  await sleep(1200)
  run('uitest dumpLayout -p /data/local/tmp/p48_m.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p48_m.json .verify/p48_m.json`, { encoding: 'utf8' })
  const j = JSON.parse(require('fs').readFileSync('.verify/p48_m.json', 'utf8'))
  let hit = null;
  (function walk(n) {
    const a = n.attributes || {}
    if (!hit && a.text === '设置') hit = a.bounds
    if (n.children) n.children.forEach(walk)
  })(j)
  console.log('menu 设置 entry:', hit || 'NOT FOUND')
  if (hit) {
    const m = hit.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
    const x = (parseInt(m[1]) + parseInt(m[3])) / 2
    const y = (parseInt(m[2]) + parseInt(m[4])) / 2
    console.log(run(`uitest uiInput click ${x} ${y}`))
    await sleep(1500)
    run('uitest dumpLayout -p /data/local/tmp/p48_s.json')
    execSync(`${HDC} -t ${T} file recv /data/local/tmp/p48_s.json .verify/p48_s.json`, { encoding: 'utf8' })
    const j2 = JSON.parse(require('fs').readFileSync('.verify/p48_s.json', 'utf8'))
    const texts = [];
    (function walk(n) { if (n.attributes && n.attributes.text) texts.push(n.attributes.text); if (n.children) n.children.forEach(walk) })(j2)
    console.log('on settings:', texts.some(t => /隐私与安全|外观/.test(t)) ? 'YES' : 'NO')
    console.log(texts.filter(t => t.length > 0 && t.length < 30).slice(0, 25).join(' | '))
  }
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
