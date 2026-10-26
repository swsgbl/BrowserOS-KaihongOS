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
  // ⋮ 菜单（1254,61）点击后立即 dump（短延迟防菜单关闭）
  run('uitest uiInput click 1254 61')
  await sleep(400)
  let j = dump('.verify/p48_x_m.json')
  let t = textsOf(j)
  console.log('menu snapshot:', t.filter(x => x.length > 0 && x.length < 28 && !/BrowserOS|Bing|bookmarks|configured|engine/.test(x)).slice(0, 20).join(' | '))
  const hasSettings = t.some(x => x === 'Settings')
  console.log('has Settings item:', hasSettings)
  if (hasSettings) {
    clickText(j, 'Settings')
    await sleep(1600)
    j = dump('.verify/p48_x_set.json')
    t = textsOf(j)
    console.log('settings:', t.some(x => /Privacy & security/.test(x)) ? 'EN settings OK' : '?')
    if (clickText(j, 'Appearance')) {
      await sleep(1200)
      j = dump('.verify/p48_x_app.json')
      if (clickText(j, '中文')) {
        await sleep(1600)
        j = dump('.verify/p48_x_zh.json')
        t = textsOf(j)
        const zhOK = ['设置', '外观', '深色模式'].filter(k => t.some(x => x.includes(k)))
        console.log('switched to ZH:', zhOK.join(',') || 'FAIL')
        if (clickText(j, '返回浏览器')) {
          await sleep(1500)
          j = dump('.verify/p48_x_zhshell.json')
          t = textsOf(j)
          const zhN = t.filter(x => /[\u4e00-\u9fff]/.test(x)).length
          const enN = t.filter(x => /New tab|View agent|Import login/.test(x)).length
          console.log('final shell: zh-texts=' + zhN + ' en-residue=' + enN)
        }
      } else console.log('中文 not found in appearance')
    } else console.log('Appearance not found')
  }
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
