/**
 * P49-A 收尾验证：
 * 1) 清 ultrafast prefs（banner 恢复显示）→ 重启 → 验证 banner 中文文案 + CTA 跳转 waitlist 页中文
 * 2) 切 en → 同套英文验证
 * 3) 截图归档 evidence/p49/
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
function boundsCenter(b) { const m = b.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/); return [(parseInt(m[1]) + parseInt(m[3])) / 2, (parseInt(m[2]) + parseInt(m[4])) / 2] }
function findText(j, needle) { let hit = null; (function w(n) { const a = n.attributes || {}; if (!hit && typeof a.text === 'string' && a.text.includes(needle)) hit = a.bounds; if (n.children) n.children.forEach(w) })(j); return hit }
const clickText = (j, needle) => { const b = findText(j, needle); if (!b) return false; const [x, y] = boundsCenter(b); run(`uitest uiInput click ${x} ${y}`); return true }

async function maximize() {
  const j = dump('w_state')
  if (textsOf(j).some(x => x === '应用中心')) {
    let mb = null; (function w(n) { const a = n.attributes || {}; if (!mb && a.id === 'EnhanceMaximizeBtn') mb = a.bounds; if (n.children) n.children.forEach(w) })(j)
    if (mb) { const [x, y] = boundsCenter(mb); run(`uitest uiInput click ${x} ${y}`); await sleep(1100) }
  }
}

/** 清 ultrafast prefs：app filesDir 下 ultrafast_store */
async function clearUltrafastPrefs() {
  run('aa force-stop com.browseros.kaihong')
  await sleep(600)
  const out = run('find /data/app/el2/100/base/com.browseros.kaihong -name "*ultrafast*" 2>/dev/null || true')
  console.log('find ultrafast:', out || '(none)')
  if (out) {
    for (const f of out.split(/\r?\n/).filter(Boolean)) {
      run('rm -f "' + f.trim() + '"')
    }
    console.log('cleared')
  }
  // 保险：整个 preferences 目录里含 ultrafast 的 xml/json 都删
  const out2 = run('ls -R /data/app/el2/100/base/com.browseros.kaihong/preferences 2>/dev/null || true')
  if (out2.includes('ultrafast')) {
    run('rm -f /data/app/el2/100/base/com.browseros.kaihong/preferences/*ultrafast*')
  }
}

async function bannerFlow(locale) {
  // 重启 → 最大化 → 新标签页 banner 验证
  run('aa start -a EntryAbility -b com.browseros.kaihong')
  await sleep(3000)
  await maximize()
  let j = dump('banner_' + locale)
  shot('a3_banner_' + locale)
  let texts = textsOf(j)
  if (locale === 'zh') {
    const okBanner = texts.some(t => t.includes('更快的浏览器任务')) && texts.some(t => t.includes('Ultrafast'))
    console.log((okBanner ? '[PASS] ' : '[FAIL] ') + locale + ' banner desc (ultrafastDesc)')
    const okCta = clickText(j, '申请抢先体验')
    console.log((okCta ? '[PASS] ' : '[FAIL] ') + locale + ' banner CTA visible')
  } else {
    const okBanner = texts.some(t => t.includes('Faster browser tasks')) && texts.some(t => t.includes('Ultrafast'))
    console.log((okBanner ? '[PASS] ' : '[FAIL] ') + locale + ' banner desc (ultrafastDesc)')
    const okCta = clickText(j, 'Request early access')
    console.log((okCta ? '[PASS] ' : '[FAIL] ') + locale + ' banner CTA visible')
  }
  await sleep(1700)
  j = dump('wlpage_' + locale)
  texts = textsOf(j)
  shot('a4_waitlist_' + locale)
  if (locale === 'zh') {
    const ok = texts.some(t => t.includes('即将推出')) && texts.some(t => t.includes('加入等待名单')) && texts.some(t => t.includes('自带 Claude'))
    console.log((ok ? '[PASS] ' : '[FAIL] ') + locale + ' waitlist page zh copy — ' + texts.filter(t => t.length > 4 && t.length < 24).slice(0, 6).join('|'))
  } else {
    const ok = texts.some(t => t.includes('COMING SOON')) && texts.some(t => t.includes('Join waitlist')) && texts.some(t => t.includes('Bring your own Claude'))
    console.log((ok ? '[PASS] ' : '[FAIL] ') + locale + ' waitlist page en copy — ' + texts.filter(t => t.length > 4 && t.length < 24).slice(0, 6).join('|'))
  }
  // 返回 shell
  run('uitest uiInput keyEvent 2'); await sleep(800)
}

;(async () => {
  await clearUltrafastPrefs()
  await bannerFlow('zh')
  // 切 en：菜单→设置→English
  let j = dump('pre_sw')
  const btn = findText(j, 'about:blank')
  // 找 ⋮（omnibox 右侧最右 36px 按钮）
  let omni = null; (function w(n) { const a = n.attributes || {}; if (!omni && a.id === 'p11f_omnibox') omni = a.bounds; if (n.children) n.children.forEach(w) })(j)
  if (omni) {
    const om = omni.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
    let rm = null;
    (function w(n) { const a = n.attributes || {}; const m = (a.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/); if (m) { const x1 = parseInt(m[1]), y1 = parseInt(m[2]), x2 = parseInt(m[3]), y2 = parseInt(m[4]); if (x1 >= parseInt(om[3]) && x1 < parseInt(om[3]) + 220 && y1 >= parseInt(om[2]) - 12 && y2 <= parseInt(om[4]) + 12 && (x2 - x1) >= 30 && (x2 - x1) <= 44 && (y2 - y1) >= 30 && (y2 - y1) <= 44) { if (!rm || x1 > rm.x) rm = { x: x1, b: a.bounds } } } if (n.children) n.children.forEach(w) })(j)
    if (rm) { const [x, y] = boundsCenter(rm.b); run(`uitest uiInput click ${x} ${y}`); await sleep(1100) }
  }
  j = dump('sw_menu')
  if (clickText(j, '设置')) {
    await sleep(1400)
    j = dump('sw_set')
    // 语言在外观区：先点「外观」
    if (clickText(j, '外观')) { await sleep(900); j = dump('sw_set_app') }
    let ok = clickText(j, 'English')
    if (!ok) { run('uitest uiInput swipe 640 600 640 250'); await sleep(700); j = dump('sw_set2'); ok = clickText(j, 'English') }
    console.log((ok ? '[PASS] ' : '[FAIL] ') + 'switch to en')
    await sleep(1300)
    if (ok) {
      // 英文态：回 shell 重启清 prefs 后验证
      await clearUltrafastPrefs()
      await bannerFlow('en')
      // 恢复 zh
      run('aa force-stop com.browseros.kaihong'); await sleep(500)
      run('aa start -a EntryAbility -b com.browseros.kaihong'); await sleep(2600)
      await maximize()
      let j2 = dump('re_menu_pre')
      const om2 = (() => { let o = null; (function w(n) { const a = n.attributes || {}; if (!o && a.id === 'p11f_omnibox') o = a.bounds; if (n.children) n.children.forEach(w) })(j2); return o })()
      if (om2) {
        const mm = om2.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
        let rm2 = null;
        (function w(n) { const a = n.attributes || {}; const m = (a.bounds || '').match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/); if (m) { const x1 = parseInt(m[1]), y1 = parseInt(m[2]), x2 = parseInt(m[3]), y2 = parseInt(m[4]); if (x1 >= parseInt(mm[3]) && x1 < parseInt(mm[3]) + 220 && y1 >= parseInt(mm[2]) - 12 && y2 <= parseInt(mm[4]) + 12 && (x2 - x1) >= 30 && (x2 - x1) <= 44 && (y2 - y1) >= 30 && (y2 - y1) <= 44) { if (!rm2 || x1 > rm2.x) rm2 = { x: x1, b: a.bounds } } } if (n.children) n.children.forEach(w) })(j2)
        if (rm2) { const [x, y] = boundsCenter(rm2.b); run(`uitest uiInput click ${x} ${y}`); await sleep(1100) }
      }
      j2 = dump('re_menu')
      if (clickText(j2, 'Settings')) {
        await sleep(1400)
        j2 = dump('re_set')
        if (clickText(j2, 'Appearance')) { await sleep(900); j2 = dump('re_set_app') }
        let ok2 = clickText(j2, '中文')
        if (!ok2) { run('uitest uiInput swipe 640 600 640 250'); await sleep(700); j2 = dump('re_set2'); ok2 = clickText(j2, '中文') }
        console.log((ok2 ? '[PASS] ' : '[FAIL] ') + 'restore zh')
      }
    }
  } else {
    console.log('[FAIL] switch to en (menu)')
  }
  console.log('\ndone')
})().catch(e => { console.error('FATAL', e.message); process.exit(1) })
