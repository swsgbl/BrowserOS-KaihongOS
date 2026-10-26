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
  await sleep(2200)
  // A. en 持久化验证（重启后 shell 应全英文含计数格式）
  let j = dump('.verify/p48_v_en_shell.json')
  let t = textsOf(j)
  const shellEN = ['New tab', 'View agent', 'Import login', 'Bookmarks:'].filter(k => t.some(x => x.includes(k)))
  const shellZH = t.filter(x => /[\u4e00-\u9fff]/.test(x))
  console.log('[A] restart-persist EN shell markers:', shellEN.join(',') || 'NONE')
  console.log('[A] shell residual zh:', shellZH.length, shellZH.slice(0, 8).map(x => x.substring(0, 30)).join('|'))
  // B. 菜单 → Settings(en) → Appearance → 中文 切回
  run('uitest uiInput click 1254 61')
  await sleep(1200)
  j = dump('.verify/p48_v_m.json')
  if (!clickText(j, 'Settings')) { console.log('[B] menu Settings not found; texts:', t.slice(0, 12).join('|')); }
  await sleep(1500)
  j = dump('.verify/p48_v_set.json')
  t = textsOf(j)
  console.log('[B] settings page:', t.some(x => /Privacy|Appearance/.test(x)) ? 'EN OK' : 'LANG?')
  if (clickText(j, 'Appearance')) {
    await sleep(1200)
    j = dump('.verify/p48_v_app.json')
    if (clickText(j, '中文')) {
      await sleep(1500)
      // C. 验证切回中文
      j = dump('.verify/p48_v_zh_set.json')
      t = textsOf(j)
      const zhOK = ['设置', '外观', '深色模式'].filter(k => t.some(x => x.includes(k)))
      console.log('[C] switch back zh:', zhOK.join(',') || 'FAIL')
      // D. 返回浏览器验证 shell 中文
      if (!clickText(j, '返回浏览器')) { run('uitest uiInput keyEvent 10') }
      await sleep(1500)
      j = dump('.verify/p48_v_zh_shell.json')
      t = textsOf(j)
      const shellZH2 = t.filter(x => /[\u4e00-\u9fff]/.test(x))
      console.log('[D] shell back to zh:', shellZH2.length > 3 ? 'YES (' + shellZH2.slice(0, 4).join('|') + ')' : 'PARTIAL')
    } else console.log('[C] 中文 option not found')
  } else console.log('[B2] Appearance not found')
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
