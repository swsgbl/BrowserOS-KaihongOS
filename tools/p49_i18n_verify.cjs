const { execSync } = require('child_process')
const fs = require('fs')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const EV = 'evidence/p49'
fs.mkdirSync(EV, { recursive: true })
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 }).trim()
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
const dump = (tag) => {
  const local = `${EV}/${tag}.json`
  run('uitest dumpLayout -p /data/local/tmp/p49_d.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p49_d.json ${local}`, { encoding: 'utf8' })
  return JSON.parse(fs.readFileSync(local, 'utf8'))
}
const textsOf = (j) => { const t = []; (function w(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); if (n.children) n.children.forEach(w) })(j); return t }
function clickText(j, needle) {
  let hit = null
  ;(function w(n) {
    const a = n.attributes || {}
    if (!hit && typeof a.text === 'string' && a.text.includes(needle)) hit = a.bounds
    if (n.children) n.children.forEach(w)
  })(j)
  if (!hit) return false
  const m = hit.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
  run(`uitest uiInput click ${(parseInt(m[1]) + parseInt(m[3])) / 2} ${(parseInt(m[2]) + parseInt(m[4])) / 2}`)
  return true
}
const shot = (tag) => {
  execSync(`${HDC} -t ${T} shell "snapshot_display -f /data/local/tmp/p49_s.jpeg"`, { encoding: 'utf8', timeout: 30000 })
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p49_s.jpeg ${EV}/${tag}.jpeg`, { encoding: 'utf8' })
}
const results = []
const rec = (name, ok, detail) => { results.push([name, ok]); console.log((ok ? '[PASS] ' : '[FAIL] ') + name + (detail ? ' — ' + detail : '')) }

/** ⋮ 菜单（toolbar 最右 [1236,43][1272,79] → 1254,61）→ 返回菜单页面的 dump */
async function openMenu(tag) {
  run('uitest uiInput click 1254 61')
  await sleep(1100)
  return dump(tag)
}
/** P48 验证脚本同款坐标：toolbar 最右按钮 */

async function setLocale(target) {
  let j = await openMenu('set_menu_' + target)
  if (!clickText(j, target === 'current-zh' ? '设置' : 'Settings')) {
    // maybe locale is the other one
    if (!clickText(j, target === 'en' ? 'Settings' : '设置')) return false
  }
  await sleep(1300)
  j = dump('set_page_' + target)
  const want = target === 'en' ? 'English' : '中文'
  let clicked = clickText(j, want)
  if (!clicked) {
    run('uitest uiInput swipe 640 600 640 250')
    await sleep(700)
    j = dump('set_page2_' + target)
    clicked = clickText(j, want)
  }
  await sleep(1200)
  return clicked
}

async function verifyLocale(locale) {
  // 1) 新标签页 hero（重启 app 保证回 shell）
  run('aa force-stop com.browseros.kaihong'); await sleep(500)
  run('aa start -a EntryAbility -b com.browseros.kaihong'); await sleep(2800)
  let j = dump('nt_' + locale)
  shot('a1_newtab_' + locale)
  let texts = textsOf(j)
  if (locale === 'zh') rec('zh heroSubtitle', texts.some(t => t.includes('选择任一已连接的服务商或代理，然后直接在此标签页内开始任务')), '')
  else rec('en heroSubtitle', texts.some(t => t.includes('Pick any provider or agent you have connected')), '')

  // 2) Skills 页：⚙ 菜单 → 技能/Skills
  j = await openMenu('menu_' + locale)
  shot('a2_menu_' + locale)
  const okMenu = clickText(j, locale === 'zh' ? '技能' : 'Skills')
  rec(locale + ': menu Skills entry (i18n)', okMenu, locale === 'zh' ? '技能' : 'Skills')
  await sleep(1500)
  j = dump('skills_' + locale)
  texts = textsOf(j)
  shot('a2_skills_' + locale)
  if (locale === 'zh') {
    rec('zh skillsTitle=技能', texts.some(t => t.trim() === '技能'), '')
    rec('zh skNewSkill/skRuns/skTokensSaved', texts.some(t => t.includes('新建技能')) && texts.some(t => t.trim() === '次数') && texts.some(t => t.includes('节省令牌')), texts.filter(t => t.length < 10).slice(0, 10).join('|'))
  } else {
    rec('en skillsTitle=Skills', texts.some(t => t.trim() === 'Skills'), '')
    rec('en skNewSkill/skRuns/skTokensSaved', texts.some(t => t.includes('New skill')) && texts.some(t => t.trim() === 'Runs') && texts.some(t => t.includes('Tokens saved')), texts.filter(t => t.length < 14).slice(0, 10).join('|'))
  }
  run('uitest uiInput keyEvent 2'); await sleep(900)  // back to shell

  // 3) Ultrafast waitlist：CTA
  const cta = locale === 'zh' ? '申请抢先体验' : 'Request early access'
  j = dump('nt2_' + locale)
  const okCta = clickText(j, cta)
  rec(locale + ': ultrafast CTA (i18n)', okCta, cta)
  await sleep(1600)
  j = dump('wl_' + locale)
  texts = textsOf(j)
  shot('a3_waitlist_' + locale)
  if (locale === 'zh') {
    rec('zh waitlist 即将推出/加入等待名单/月', texts.some(t => t.includes('即将推出')) && texts.some(t => t.includes('加入等待名单')) && texts.some(t => t.includes('/月')), '')
  } else {
    rec('en waitlist COMING SOON/Join waitlist/$5/mo', texts.some(t => t.includes('COMING SOON')) && texts.some(t => t.includes('Join waitlist')) && texts.some(t => t.includes('$5')), '')
  }
  run('uitest uiInput keyEvent 2'); await sleep(700)
}

;(async () => {
  await verifyLocale('zh')
  const sw = await setLocale('en')
  rec('switch to en', sw, '')
  if (sw) {
    await verifyLocale('en')
    // 切回 zh（保持默认态给 B 部分测试）
    run('uitest uiInput keyEvent 2'); await sleep(600)
    run('uitest uiInput keyEvent 2'); await sleep(600)
    run('aa force-stop com.browseros.kaihong'); await sleep(400)
    run('aa start -a EntryAbility -b com.browseros.kaihong'); await sleep(2200)
    const back = await setLocale('zh')
    rec('restore zh', back, '')
  }
  const passed = results.filter(r => r[1]).length
  console.log(`\n== p49 i18n verify: ${passed}/${results.length} PASS ==`)
  process.exit(passed === results.length ? 0 : 1)
})().catch(e => { console.error('FATAL', e.message); process.exit(1) })
