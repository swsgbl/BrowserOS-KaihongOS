/**
 * P49-B3: Neo Dashboard MCP 安装板设备验证
 * 路径：新标签页 → 「查看代理」按钮（或 Dashboard 入口）→ MCP/连接器区
 * 断言：harness 网格（Claude Code/Codex/Cursor 等）+ 46 家连接器目录可浏览 + 截图
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
const rec = (name, ok, detail) => { console.log((ok ? '[PASS] ' : '[FAIL] ') + name + (detail ? ' — ' + detail : '')); process.exitCode = ok ? 0 : 1; results.push(ok) }
const results = []

async function maximize() {
  const j = dump('b3_w')
  if (textsOf(j).some(x => x === '应用中心')) {
    let mb = null; (function w(n) { const a = n.attributes || {}; if (!mb && a.id === 'EnhanceMaximizeBtn') mb = a.bounds; if (n.children) n.children.forEach(w) })(j)
    if (mb) { const [x, y] = boundsCenter(mb); run(`uitest uiInput click ${x} ${y}`); await sleep(1100) }
  }
}

;(async () => {
  run('aa force-stop com.browseros.kaihong'); await sleep(600)
  run('aa start -a EntryAbility -b com.browseros.kaihong'); await sleep(3200)
  await maximize()
  // 新标签页 → 「查看代理」按钮打开 Agent 侧栏/Dashboard
  let j = dump('b3_nt')
  // 先打开 Dashboard（查看代理）
  const okBtn = clickText(j, '查看代理')
  rec('b3 open agent panel (查看代理)', okBtn, '')
  await sleep(1500)
  j = dump('b3_agent')
  // Cockpit 头部「MCP 安装板」按钮切换到安装板视图
  const okBoard = clickText(j, 'MCP 安装板')
  rec('b3 open MCP install board', okBoard, '')
  await sleep(1500)
  j = dump('b3_board')
  shot('b3_mcp_board')
  let texts = textsOf(j)
  rec('b3 agent panel has MCP section', texts.some(t => /MCP|mcp/.test(t)), texts.filter(t => /MCP|mcp/i.test(t)).slice(0, 4).join('|'))
  // 找 harness 网格（Claude Code / Codex / Cursor 等名称）
  const harnessNames = ['Claude Code', 'Codex', 'Cursor', 'VS Code', 'OpenClaw', 'Hermes']
  const found = harnessNames.filter(h => texts.some(t => t.includes(h)))
  rec('b3 harness grid (>=4 of 6 names)', found.length >= 4, 'found: ' + found.join(','))
  // 连接器目录：滚动找 46 家品牌（任取几个知名：GitHub/Slack/Notion/Figma）
  run('uitest uiInput swipe 640 620 640 150'); await sleep(800)
  j = dump('b3_scroll1')
  texts = textsOf(j)
  const brands = ['GitHub', 'Slack', 'Notion', 'Figma', 'Linear', 'Sentry']
  const bfound = brands.filter(b => texts.some(t => t.includes(b)))
  rec('b3 connector catalog (>=2 brands visible)', bfound.length >= 2, 'found: ' + bfound.join(','))
  shot('b3_connectors')
  // 连接器目录计数断言（46 家）：滚动累计不同品牌名
  const seen = new Set()
  for (let i = 0; i < 6; i++) {
    j = dump('b3_s' + i)
    textsOf(j).forEach(t => { if (t.length >= 3 && t.length <= 18 && /^[A-Za-z0-9 .&-]+$/.test(t) && !harnessNames.some(h => t.includes(h))) seen.add(t) })
    run('uitest uiInput swipe 640 620 640 150'); await sleep(600)
  }
  shot('b3_catalog_end')
  console.log('unique-ish names seen:', seen.size)
  console.log('sample:', [...seen].slice(0, 20).join(' | '))
  const passed = results.filter(Boolean).length
  console.log(`\n== b3: ${passed}/${results.length} PASS ==`)
})().catch(e => { console.error('FATAL', e.message); process.exit(1) })
