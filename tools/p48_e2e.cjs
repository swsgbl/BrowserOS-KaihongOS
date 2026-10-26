const { execSync } = require('child_process')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 })
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
;(async () => {
  // 1. 拉前台 + dump 确认
  run('aa start -a EntryAbility -b com.browseros.kaihong')
  await sleep(1500)
  // 2. 点 omnibox 并输入 browseros://settings 回车
  console.log(run('uitest uiInput click 712 61'))
  await sleep(800)
  console.log(run('uitest uiInput inputText 712 61 browseros://settings'))
  await sleep(500)
  console.log(run('uitest uiInput keyEvent 7'))  // Enter
  await sleep(1800)
  // 3. dump 验证
  run('uitest dumpLayout -p /data/local/tmp/p48_l4.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p48_l4.json .verify/p48_l4.json`, { encoding: 'utf8' })
  const j = JSON.parse(require('fs').readFileSync('.verify/p48_l4.json', 'utf8'))
  const texts = []
  ;(function walk(n) { if (n.attributes && n.attributes.text) texts.push(n.attributes.text); if (n.children) n.children.forEach(walk) })(j)
  const onSettings = texts.some(t => /隐私与安全|外观|Privacy|Appearance/.test(t))
  console.log('on settings page:', onSettings ? 'YES' : 'NO')
  console.log(texts.filter(t => t.length > 0 && t.length < 40).slice(0, 30).join(' | '))
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
