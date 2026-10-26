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
const clickText = (j, want) => {
  let hit = null;
  (function w(n) { const a = n.attributes || {}; if (!hit && a.text === want) hit = a.bounds; if (n.children) n.children.forEach(w) })(j)
  if (!hit) return false
  const m = hit.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
  run(`uitest uiInput click ${(parseInt(m[1]) + parseInt(m[3])) / 2} ${(parseInt(m[2]) + parseInt(m[4])) / 2}`)
  return true
}
;(async () => {
  run('aa start -a EntryAbility -b com.browseros.kaihong')
  await sleep(2000)
  // ⋮ 菜单 → 设置
  run('uitest uiInput click 1254 61')
  await sleep(1200)
  let j = dump('.verify/p48_m2.json')
  if (!clickText(j, '设置')) { console.log('STEP1 FAIL: menu 设置 not found'); process.exit(1) }
  await sleep(1500)
  // 外观 → English
  j = dump('.verify/p48_s3.json')
  if (!clickText(j, '外观')) { console.log('STEP2 FAIL: 外观 not found'); process.exit(1) }
  await sleep(1200)
  j = dump('.verify/p48_app2.json')
  if (!clickText(j, 'English')) { console.log('STEP3 FAIL: English not found'); process.exit(1) }
  await sleep(1500)
  // 验证：设置页应全英文
  j = dump('.verify/p48_en2.json')
  const texts = textsOf(j)
  const enOK = ['Settings', 'Search', 'Appearance', 'Privacy', 'Dark mode'].filter(k => texts.some(t => t.includes(k)))
  const zhLeft = texts.filter(t => /[\u4e00-\u9fff]/.test(t) && !/中文/.test(t))
  console.log('EN markers:', enOK.join(','))
  console.log('residual zh (excl 中文 option):', zhLeft.length, zhLeft.slice(0, 5).join('|'))
  // 返回浏览器（返回浏览器按钮 / Back）验证 shell 英文
  if (!clickText(j, 'Back to browser')) { run('uitest uiInput keyEvent 10'); await sleep(800); run('uitest uiInput keyEvent 10') }
  await sleep(1500)
  j = dump('.verify/p48_en_shell.json')
  const st = textsOf(j)
  const shellEN = ['New tab', 'View agent', 'Import login', 'Bookmarks:'].filter(k => st.some(t => t.includes(k)))
  const shellZH = st.filter(t => /[\u4e00-\u9fff]/.test(t))
  console.log('shell EN markers:', shellEN.join(','))
  console.log('shell residual zh:', shellZH.length, shellZH.slice(0, 6).map(x => x.substring(0, 24)).join('|'))
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
