const { execSync } = require('child_process')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 })
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
;(async () => {
  run('aa start -a EntryAbility -b com.browseros.kaihong')
  await sleep(2500)
  run('uitest dumpLayout -p /data/local/tmp/p48_z.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p48_z.json .verify/p48_final_zh.json`, { encoding: 'utf8' })
  const j = JSON.parse(require('fs').readFileSync('.verify/p48_final_zh.json', 'utf8'))
  const t = [];
  (function w(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); if (n.children) n.children.forEach(w) })(j)
  const zhOK = ['新标签页', '查看代理', '导入登录态', '书签'].filter(k => t.some(x => x.includes(k)))
  const enLeft = t.filter(x => /New tab|View agent|Import login/.test(x))
  console.log('zh restored markers:', zhOK.join(','))
  console.log('en residue:', enLeft.length ? enLeft.join('|') : 'NONE')
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
