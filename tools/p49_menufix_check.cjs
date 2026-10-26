// P49: getter→method 修复后菜单验证 + 解锁后首启等待
const { execSync } = require('child_process')
const fs = require('fs')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 }).trim()
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
const dump = (local) => {
  run('uitest dumpLayout -p /data/local/tmp/p49_v.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p49_v.json ${local}`, { encoding: 'utf8' })
  return JSON.parse(fs.readFileSync(local, 'utf8'))
}
const textsOf = (j) => { const t = []; (function w(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); if (n.children) n.children.forEach(w) })(j); return t }
;(async () => {
  // 前台确认
  run('aa start -a EntryAbility -b com.browseros.kaihong')
  await sleep(2500)
  // 点 ⋮（1254,61）
  run('uitest uiInput click 1254 61')
  await sleep(1300)
  const j = dump('evidence/p49/fix_menu.json')
  const texts = textsOf(j)
  const menu = texts.filter(t => /新建|设置|退出|技能|历史|书签|下载|密码|定时|放大|缩小|阅读|填充|开发|查找|帮助/.test(t))
  console.log('menu items:', menu.join(' | ') || 'NONE')
  process.exit(menu.length >= 10 ? 0 : 1)
})().catch(e => { console.error('FAIL', e.message); process.exit(1) })
