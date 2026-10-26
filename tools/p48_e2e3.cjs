const { execSync } = require('child_process')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 })
const recvDump = (local) => {
  run('uitest dumpLayout -p /data/local/tmp/p48_d.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p48_d.json ${local}`, { encoding: 'utf8' })
  return JSON.parse(require('fs').readFileSync(local, 'utf8'))
}
const textsOf = (j) => { const t = []; (function w(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); if (n.children) n.children.forEach(w) })(j); return t }
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
const clickText = (j, want) => {
  let hit = null;
  (function w(n) { const a = n.attributes || {}; if (!hit && a.text === want) hit = a.bounds; if (n.children) n.children.forEach(w) })(j)
  if (!hit) return null
  const m = hit.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
  run(`uitest uiInput click ${(parseInt(m[1]) + parseInt(m[3])) / 2} ${(parseInt(m[2]) + parseInt(m[4])) / 2}`)
  return hit
}
;(async () => {
  // 1. 当前在设置页（p48_s 状态）→ 点左导航"外观"
  let j = recvDump('.verify/p48_s2.json')
  if (!clickText(j, '外观')) { console.log('外观 not visible, scroll nav'); }
  await sleep(1200)
  j = recvDump('.verify/p48_app.json')
  let texts = textsOf(j)
  console.log('appearance section:', texts.some(t => /深色模式|Dark mode/.test(t)) ? 'YES(zh)' : texts.some(t => /Dark/.test(t)) ? 'YES(en)' : 'NO')
  // 2. 点 English
  const ok = clickText(j, 'English')
  console.log('click English:', ok ? 'clicked ' + ok : 'NOT FOUND')
  await sleep(1500)
  // 3. dump 验证整页英文
  j = recvDump('.verify/p48_en.json')
  texts = textsOf(j)
  const zhCount = texts.filter(t => /[\u4e00-\u9fff]/.test(t) && !/中文/.test(t)).length
  const enHits = ['Settings', 'Appearance', 'Dark mode', 'Theme', 'Language'].filter(k => texts.some(t => t.includes(k)))
  console.log('EN markers:', enHits.join(','))
  console.log('residual zh texts:', zhCount)
  console.log(texts.filter(t => t.length > 0 && t.length < 40).slice(0, 25).join(' | '))
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
