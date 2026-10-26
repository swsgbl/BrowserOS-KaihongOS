/**
 * P49 i18n 验证 v3 —— 自适应窗口偏移版
 * 关键修正：
 * 1) 解锁后 app 是自由窗口（偏移 ~241,143），⋮ 按钮坐标必须每次 dump 动态解析
 * 2) 先最大化窗口（点 maximize 按钮或双击标题栏）恢复全屏 1280x800
 */
const { execSync } = require('child_process')
const fs = require('fs')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const T = '192.168.161.137:10178'
const EV = 'evidence/p49'
const run = (cmd) => execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', timeout: 30000 }).trim()
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
const dump = (tag) => {
  const local = `${EV}/${tag}.json`
  run('uitest dumpLayout -p /data/local/tmp/p49_d.json')
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p49_d.json ${local}`, { encoding: 'utf8' })
  return JSON.parse(fs.readFileSync(local, 'utf8'))
}
const textsOf = (j) => { const t = []; (function w(n) { if (n.attributes && n.attributes.text) t.push(n.attributes.text); if (n.children) n.children.forEach(w) })(j); return t }
const shot = (tag) => {
  execSync(`${HDC} -t ${T} shell "snapshot_display -f /data/local/tmp/p49_s.jpeg"`, { encoding: 'utf8', timeout: 30000 })
  execSync(`${HDC} -t ${T} file recv /data/local/tmp/p49_s.jpeg ${EV}/${tag}.jpeg`, { encoding: 'utf8' })
}
function boundsCenter(b) {
  const m = b.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
  return [ (parseInt(m[1]) + parseInt(m[3])) / 2, (parseInt(m[2]) + parseInt(m[4])) / 2 ]
}
function findText(j, needle) {
  let hit = null
  ;(function w(n) {
    const a = n.attributes || {}
    if (!hit && typeof a.text === 'string' && a.text.includes(needle)) hit = a.bounds
    if (n.children) n.children.forEach(w)
  })(j)
  return hit
}
const clickB = (b) => { const [x, y] = boundsCenter(b); run(`uitest uiInput click ${x} ${y}`) }
const clickText = (j, needle) => { const b = findText(j, needle); if (!b) return false; clickB(b); return true }

/** 最大化 app 窗口：若处于自由窗口，双击标题栏（enhanceAppLabel 行） */
async function maximize() {
  let j = dump('w_state')
  const t = textsOf(j)
  const freeWin = t.some(x => x === '应用中心') || t.some(x => x === '文件管理器')
  if (freeWin) {
    // 点窗口右上 Maximize 按钮（自由窗口标题栏在窗口内容区顶部）
    let maxBtn = null;
    (function w(n) { const a = n.attributes || {}; if (!maxBtn && a.id === 'EnhanceMaximizeBtn') maxBtn = a.bounds; if (n.children) n.children.forEach(w) })(j)
    if (maxBtn) {
      const [x, y] = boundsCenter(maxBtn)
      run(`uitest uiInput click ${x} ${y}`)
      await sleep(1200)
      j = dump('w_state2')
      const still = textsOf(j).some(x => x === '应用中心')
      console.log('  (maximize btn: still free-window=' + still + ')')
    }
  }
  return true
}

/** 找 ⋮ 菜单按钮：窗口 toolbar 行内 omnibox 右侧第 5 个 36px 按钮 = 最右侧 */
function findMenuBtn(j) {
  // omnibox: 文本 about:blank 或 p11f_omnibox id
  let omni = null;
  (function w(n) { const a = n.attributes || {}; if (!omni && a.id === 'p11f_omnibox') omni = a.bounds; if (n.children) n.children.forEach(w) })(j)
  if (!omni) {
    (function w(n) { const a = n.attributes || {}; if (!omni && a.id && String(a.id).includes('omnibox')) omni = a.bounds; if (n.children) n.children.forEach(w) })(j)
  }
  if (!omni) return null
  const om = omni.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
  const oy1 = parseInt(om[2]), ox2 = parseInt(om[3]), oy2 = parseInt(om[4])
  // 找 omnibox 右侧、同一行的最后一个 36px 方块（toolbar 按钮）= ⋮ 菜单
  let rightmost = null
  ;(function w(n) {
    const a = n.attributes || {}
    const m = (a.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
    if (m) {
      const x1 = parseInt(m[1]), yy1 = parseInt(m[2]), xx2 = parseInt(m[3]), yy2 = parseInt(m[4])
      const wpx = xx2 - x1, hpx = yy2 - yy1
      if (x1 >= ox2 && x1 < ox2 + 220 && yy1 >= oy1 - 12 && yy2 <= oy2 + 12 && wpx >= 30 && wpx <= 44 && hpx >= 30 && hpx <= 44) {
        if (!rightmost || x1 > rightmost.x) rightmost = { x: x1, b: a.bounds }
      }
    }
    if (n.children) n.children.forEach(w)
  })(j)
  return rightmost ? rightmost.b : null
}

const results = []
const rec = (name, ok, detail) => { results.push([name, ok]); console.log((ok ? '[PASS] ' : '[FAIL] ') + name + (detail ? ' — ' + detail : '')) }

async function openMenu(tag) {
  let j = dump('pre_' + tag)
  const btn = findMenuBtn(j)
  if (!btn) return j
  clickB(btn)
  await sleep(1100)
  return dump(tag)
}

async function setLocale(target) {
  await maximize()
  let j = await openMenu('set_m_' + target)
  // 菜单必须在 dump 里出现菜单项才继续
  const hasItems = textsOf(j).some(t => t === '设置' || t === 'Settings')
  if (!hasItems) { console.log('  (menu did not open for ' + target + ')'); return false }
  const wantMenu = textsOf(j).some(t => t === '设置') ? '设置' : 'Settings'
  clickText(j, wantMenu)
  await sleep(1400)
  j = dump('set_p_' + target)
  // 语言在外观区：先点「外观/Appearance」
  const appearZh = textsOf(j).some(t => t === '外观')
  const appear = appearZh ? '外观' : 'Appearance'
  if (clickText(j, appear)) { await sleep(900); j = dump('set_pa_' + target) }
  const want = target === 'en' ? 'English' : '中文'
  let clicked = clickText(j, want)
  if (!clicked) {
    run('uitest uiInput swipe 640 600 640 250'); await sleep(700)
    j = dump('set_p2_' + target)
    clicked = clickText(j, want)
  }
  await sleep(1200)
  return clicked
}

async function verifyLocale(locale) {
  run('aa force-stop com.browseros.kaihong'); await sleep(600)
  run('aa start -a EntryAbility -b com.browseros.kaihong'); await sleep(3000)
  await maximize()
  await maximize()  // 双保险：首启常为自由窗口
  let j = dump('nt_' + locale)
  shot('a1_newtab_' + locale)
  let texts = textsOf(j)
  if (locale === 'zh') rec('zh heroSubtitle', texts.some(t => t.includes('选择任一已连接的服务商或代理，然后直接在此标签页内开始任务')), '')
  else rec('en heroSubtitle', texts.some(t => t.includes('Pick any provider or agent you have connected')), '')

  // Skills
  j = await openMenu('menu_' + locale)
  shot('a2_menu_' + locale)
  const okMenu = clickText(j, locale === 'zh' ? '技能' : 'Skills')
  rec(locale + ': menu Skills entry (i18n)', okMenu, '')
  await sleep(1600)
  j = dump('skills_' + locale)
  texts = textsOf(j)
  shot('a2_skills_' + locale)
  if (locale === 'zh') {
    rec('zh skillsTitle=技能', texts.some(t => t.trim() === '技能'), '')
    rec('zh skNewSkill/skRuns/skTokensSaved', texts.some(t => t.includes('新建技能')) && texts.some(t => t.trim() === '次数') && texts.some(t => t.includes('节省令牌')), texts.filter(t => t.length < 10).slice(0, 8).join('|'))
  } else {
    rec('en skillsTitle=Skills', texts.some(t => t.trim() === 'Skills'), '')
    rec('en skNewSkill/skRuns/skTokensSaved', texts.some(t => t.includes('New skill')) && texts.some(t => t.trim() === 'Runs') && texts.some(t => t.includes('Tokens saved')), texts.filter(t => t.length < 14).slice(0, 8).join('|'))
  }
  run('uitest uiInput keyEvent 2'); await sleep(1000)

  // Ultrafast CTA（banner 可能在折叠下方：找不到先下滑再试）
  j = dump('nt2_' + locale)
  const cta = locale === 'zh' ? '申请抢先体验' : 'Request early access'
  let okCta = clickText(j, cta)
  if (!okCta) {
    run('uitest uiInput swipe 640 550 640 200'); await sleep(700)
    j = dump('nt2b_' + locale)
    okCta = clickText(j, cta)
  }
  rec(locale + ': ultrafast CTA (i18n)', okCta, cta)
  await sleep(1700)
  j = dump('wl_' + locale)
  texts = textsOf(j)
  shot('a3_waitlist_' + locale)
  if (locale === 'zh') {
    rec('zh waitlist 即将推出/加入等待名单/月', texts.some(t => t.includes('即将推出')) && texts.some(t => t.includes('加入等待名单')) && texts.some(t => t.includes('/月')), texts.filter(t => t.length > 3 && t.length < 16).slice(0, 6).join('|'))
  } else {
    rec('en waitlist COMING SOON/Join waitlist/$5', texts.some(t => t.includes('COMING SOON')) && texts.some(t => t.includes('Join waitlist')) && texts.some(t => t.includes('$5')), texts.filter(t => t.length > 3 && t.length < 16).slice(0, 6).join('|'))
  }
  run('uitest uiInput keyEvent 2'); await sleep(800)
}

;(async () => {
  await verifyLocale('zh')
  // 回 shell 再切 en
  run('aa force-stop com.browseros.kaihong'); await sleep(500)
  run('aa start -a EntryAbility -b com.browseros.kaihong'); await sleep(2400)
  const sw = await setLocale('en')
  rec('switch to en', sw, '')
  if (sw) {
    await verifyLocale('en')
    run('uitest uiInput keyEvent 2'); await sleep(600)
    run('aa force-stop com.browseros.kaihong'); await sleep(500)
    run('aa start -a EntryAbility -b com.browseros.kaihong'); await sleep(2400)
    const back = await setLocale('zh')
    rec('restore zh', back, '')
  }
  const passed = results.filter(r => r[1]).length
  console.log(`\n== p49 i18n verify: ${passed}/${results.length} PASS ==`)
  process.exit(passed === results.length ? 0 : 1)
})().catch(e => { console.error('FATAL', e.message); process.exit(1) })
