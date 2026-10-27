// P53 E2E v2: 任务栏 BrowserOS 图标拉回 → ⋮ → 设置 → 导入向导 → 手动输入 → 执行
const { execFileSync } = require('child_process')
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe'
const T = '192.168.161.137:10178'
const fs = require('fs')
const EV = 'D:/BrowserOS - KaihongOS/evidence/p53'

function sh(cmd) {
  try { return execFileSync(HDC, ['-t', T, 'shell', cmd], { encoding: 'utf8', timeout: 20000 }) }
  catch (e) { return (e.stdout || '') + (e.stderr || '') }
}
function sleep(ms) { execFileSync('ping', ['-n', String(Math.floor(ms / 1000) + 1), '127.0.0.1'], { stdio: 'ignore' }) }
function dump(name) {
  sh('uitest dumpLayout -p /data/local/tmp/' + name + '.json')
  const winPath = 'D:\\BrowserOS - KaihongOS\\evidence\\p53\\' + name + '.json'
  try { execFileSync(HDC, ['-t', T, 'file', 'recv', '/data/local/tmp/' + name + '.json', winPath], { encoding: 'utf8' }) } catch (e) { }
  try { return JSON.parse(fs.readFileSync(EV + '/' + name + '.json', 'utf8')) } catch (e) { console.error('dump-parse-fail', name); return null }
}
function nodes(layout) {
  const out = []
  function walk(n) {
    if (!n) return
    if (n.attributes) out.push(n.attributes)
    ; (n.children || []).forEach(walk)
  }
  walk(layout)
  return out
}
function center(attrs) {
  const b = (attrs.bounds || '').match(/[\d.]+/g) || []
  if (b.length < 4) return null
  return { x: Math.round((parseFloat(b[0]) + parseFloat(b[2])) / 2), y: Math.round((parseFloat(b[1]) + parseFloat(b[3])) / 2) }
}
function findByText(layout, label, exact) {
  for (const a of nodes(layout)) {
    if (a.text && (exact ? a.text === label : a.text.includes(label))) {
      const c = center(a)
      if (c) return { ...c, text: a.text, id: a.id, type: a.type }
    }
  }
  return null
}

// 0) aa start 拉前台（比点任务栏可靠）
sh('aa start -a EntryAbility -b com.browseros.kaihong')
sleep(2500)
let L = dump('v0')
const appTitle = findByText(L, 'BrowserOS', true)
console.log('V0 window ok:', appTitle ? 'yes' : 'no')

// 找浏览器 UI 特征（地址栏/标签）确认前台是 app 而非桌面
const feature = findByText(L, 'Example Domain') || findByText(L, '新建标签页')
if (!feature) {
  // 点任务栏 BrowserOS 图标
  const dockIcon = findByText(L, 'BrowserOS')
  if (dockIcon) { sh('uitest uiInput click ' + dockIcon.x + ' ' + dockIcon.y); sleep(1500) }
  L = dump('v0b')
}

// 1) 找 ⋮（更多菜单）。历史经验:菜单在顶栏右侧。
let menu = findByText(L, '⋮')
if (!menu) menu = findByText(L, '更多')
if (!menu) {
  // dump 顶栏所有 Image/Button 找可点击
  console.log('V0 texts:', nodes(L).filter(a => a.text).map(a => a.text).slice(0, 40).join(' | '))
  console.error('FAIL: no menu button found')
  process.exit(1)
}
console.log('click menu', menu.x, menu.y)
sh('uitest uiInput click ' + menu.x + ' ' + menu.y)
sleep(1200)
L = dump('v1')
const settings = findByText(L, '设置')
if (!settings) { console.error('FAIL: settings not in menu'); console.log('V1:', nodes(L).filter(a => a.text).map(a => a.text).slice(0, 40).join(' | ')); process.exit(1) }
sh('uitest uiInput click ' + settings.x + ' ' + settings.y)
sleep(1500)

// 2) 设置页 → 导入向导
L = dump('v2')
const wiz = findByText(L, '导入向导')
if (!wiz) { console.error('FAIL: no wizard entry'); console.log('V2:', nodes(L).filter(a => a.text).map(a => a.text).slice(0, 60).join(' | ')); process.exit(1) }
console.log('click wizard', wiz.x, wiz.y)
sh('uitest uiInput click ' + wiz.x + ' ' + wiz.y)
sleep(1500)

// 3) Step1 → 手动输入
L = dump('v3')
const manual = findByText(L, '手动输入')
if (!manual) { console.error('FAIL: step1'); process.exit(1) }
sh('uitest uiInput click ' + manual.x + ' ' + manual.y)
sleep(600)
L = dump('v3b')
const n1 = findByText(L, '下一步')
if (!n1) { console.error('FAIL: next1'); process.exit(1) }
sh('uitest uiInput click ' + n1.x + ' ' + n1.y)
sleep(800)

// 4) Step2 输入 3 字段
L = dump('v4')
const inputs = nodes(L).filter(a => (a.type || '').toLowerCase() === 'textinput').map(a => center(a)).filter(Boolean)
console.log('inputs:', JSON.stringify(inputs))
if (inputs.length < 3) { console.error('FAIL: need 3 inputs, got', inputs.length); process.exit(1) }
sh('uitest uiInput click ' + inputs[0].x + ' ' + inputs[0].y); sleep(400)
sh('uitest uiInput input p53test.example.com'); sleep(400)
sh('uitest uiInput click ' + inputs[1].x + ' ' + inputs[1].y); sleep(400)
sh('uitest uiInput input p53_session'); sleep(400)
sh('uitest uiInput click ' + inputs[2].x + ' ' + inputs[2].y); sleep(400)
sh('uitest uiInput input p53_value_abc123'); sleep(400)
sh('uitest uiInput keyEvent 2'); sleep(600)  // 收起输入法

// 5) 下一步 → 预览
L = dump('v5')
const n2 = findByText(L, '下一步')
if (!n2) { console.error('FAIL: next2 after inputs'); console.log('V5:', nodes(L).filter(a => a.text).map(a => a.text).join(' | ').substring(0, 400)); process.exit(1) }
sh('uitest uiInput click ' + n2.x + ' ' + n2.y)
sleep(1000)

// 6) 预览 → 执行导入
L = dump('v6')
console.log('V6 preview:', nodes(L).filter(a => a.text).map(a => a.text).slice(0, 20).join(' | '))
const exec = findByText(L, '执行导入')
if (!exec) { console.error('FAIL: no exec btn'); process.exit(1) }
sh('uitest uiInput click ' + exec.x + ' ' + exec.y)
sleep(2500)

// 7) 结果页
L = dump('v7')
const ts = nodes(L).filter(a => a.text).map(a => a.text).join(' | ')
console.log('V7 result:', ts.substring(0, 400))
console.log('WIZARD E2E:', ts.includes('导入完成') ? 'PASS' : (ts.includes('正在导入') ? 'TIMEOUT-CHECK' : 'FAIL'))
