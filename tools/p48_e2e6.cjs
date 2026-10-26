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
  // dock 设置图标（zh 验证过的 [1072,720][1100,733] → 中心 1086,726）
  run('aa start -a EntryAbility -b com.browseros.kaihong')
  await sleep(1800)
  run('uitest uiInput click 1086 726')
  await sleep(1800)
  let j = dump('.verify/p48_w_set.json')
  let t = textsOf(j)
  const onSet = t.some(x => /Privacy & security|隐私与安全/.test(x))
  console.log('[1] dock→settings:', onSet ? 'YES' : 'NO')
  const isEn = t.some(x => /Appearance/.test(x))
  console.log('[1] settings lang:', isEn ? 'EN' : 'ZH?')
  // 点 Appearance / 外观
  const clicked = clickText(j, 'Appearance') || clickText(j, '外观')
  console.log('[2] appearance clicked:', clicked)
  await sleep(1200)
  j = dump('.verify/p48_w_app.json')
  t = textsOf(j)
  console.log('[2] appearance section:', t.some(x => /Dark mode|深色模式/.test(x)) ? 'OK' : 'FAIL')
  // 点 中文
  const zh = clickText(j, '中文')
  console.log('[3] click 中文:', zh)
  await sleep(1600)
  j = dump('.verify/p48_w_zh.json')
  t = textsOf(j)
  const zhOK = ['设置', '外观', '深色模式', '语言'].filter(k => t.some(x => x.includes(k)))
  console.log('[4] page switched to zh:', zhOK.join(',') || 'FAIL')
  // 返回浏览器
  if (!clickText(j, '返回浏览器')) run('uitest uiInput keyEvent 10')
  await sleep(1500)
  j = dump('.verify/p48_w_zh_shell.json')
  t = textsOf(j)
  const zhShell = t.filter(x => /[\u4e00-\u9fff]/.test(x))
  const enLeft = t.filter(x => /New tab|View agent|Import login/.test(x))
  console.log('[5] shell zh count:', zhShell.length, zhShell.slice(0, 5).join('|'))
  console.log('[5] shell en residue:', enLeft.length ? enLeft.join('|') : 'NONE')
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
