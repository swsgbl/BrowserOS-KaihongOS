// P53 E2E: 驱动设置→导入向导→手动输入→导入执行→hilog 取证
const { execFileSync } = require('child_process')
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe'
const T = '192.168.161.137:10178'
const fs = require('fs')
const EV = 'D:/BrowserOS - KaihongOS/evidence/p53'

function sh(cmd) {
  try { return execFileSync(HDC, ['-t', T, 'shell', cmd], { encoding: 'utf8', timeout: 20000, shell: false }) }
  catch (e) { return (e.stdout || '') + (e.stderr || '') }
}
function sleep(ms) { execFileSync('ping', ['-n', String(Math.floor(ms / 1000) + 1), '127.0.0.1'], { stdio: 'ignore' }) }
function dump(name) {
  sh('uitest dumpLayout -p /data/local/tmp/' + name + '.json')
  const local = EV + '/' + name + '.json'
  const winPath = 'D:\\BrowserOS - KaihongOS\\evidence\\p53\\' + name + '.json'
  try {
    const out = execFileSync(HDC, ['-t', T, 'file', 'recv', '/data/local/tmp/' + name + '.json', winPath], { encoding: 'utf8' })
    if (!/FileTransfer finish/.test(out)) console.error('recv no-finish marker:', out)
  } catch (e) { console.error('recv fail', name, (e.stderr || e.message || '').substring(0, 200)) }
  try { return JSON.parse(fs.readFileSync(local, 'utf8')) } catch (e) { console.error('parse fail', name, e.message.substring(0, 100)); return null }
}
function texts(layout) {
  const out = []
  function walk(n) {
    if (!n) return
    if (n.attributes && n.attributes.text) out.push(n.attributes.text + '@' + Math.round((n.attributes.bounds || '').split(',').slice(0, 2).join(',')))
    ; (n.children || []).forEach(walk)
  }
  walk(layout)
  return out
}
function findBtn(layout, label) {
  let hit = null
  function walk(n) {
    if (!n || hit) return
    if (n.attributes && n.attributes.text && n.attributes.text.includes(label)) {
      const b = (n.attributes.bounds || '').match(/[\d.]+/g) || []
      if (b.length >= 4) {
        const x = (parseFloat(b[0]) + parseFloat(b[2])) / 2, y = (parseFloat(b[1]) + parseFloat(b[3])) / 2
        hit = { x: Math.round(x), y: Math.round(y), text: n.attributes.text }
      }
    }
    ; (n.children || []).forEach(walk)
  }
  walk(layout)
  return hit
}

// 0) 拉前台
sh('aa start -a EntryAbility -b com.browseros.kaihong')
sleep(2500)

// 1) dump 找 ⋮ 菜单按钮（顶栏）
let L = dump('w1')
if (!L) { console.error('FAIL: w1 dump'); process.exit(1) }
let ts = texts(L).join(' | ')
console.log('W1:', ts.substring(0, 400))
// 找「设置」文字（菜单可能需先点 ⋮）
let settings = findBtn(L, '设置')
if (!settings) {
  // 找 ⋮ 或 菜单
  const menu = findBtn(L, '⋮') || findBtn(L, '菜单') || findBtn(L, '更多')
  if (menu) {
    console.log('click menu at', menu.x, menu.y)
    sh('uitest uiInput click ' + menu.x + ' ' + menu.y)
    sleep(1200)
    L = dump('w1m')
    settings = findBtn(L, '设置')
  }
}
if (!settings) { console.error('FAIL: no settings entry. texts=', ts.substring(0, 600)); process.exit(1) }
console.log('click settings at', settings.x, settings.y)
sh('uitest uiInput click ' + settings.x + ' ' + settings.y)
sleep(1500)

// 2) 设置页找「导入向导」
L = dump('w2')
ts = texts(L).join(' | ')
console.log('W2:', ts.substring(0, 500))
const wiz = findBtn(L, '导入向导')
if (!wiz) { console.error('FAIL: no ImportWizard entry on settings'); process.exit(1) }
console.log('click wizard at', wiz.x, wiz.y)
sh('uitest uiInput click ' + wiz.x + ' ' + wiz.y)
sleep(1500)

// 3) 向导 Step1: 选「手动输入」
L = dump('w3')
ts = texts(L).join(' | ')
console.log('W3:', ts.substring(0, 500))
const manual = findBtn(L, '手动输入')
if (!manual) { console.error('FAIL: wizard step1 no manual option'); process.exit(1) }
console.log('click manual at', manual.x, manual.y)
sh('uitest uiInput click ' + manual.x + ' ' + manual.y)
sleep(800)
// 下一步
L = dump('w3b')
const next1 = findBtn(L, '下一步')
if (!next1) { console.error('FAIL: no next btn'); process.exit(1) }
sh('uitest uiInput click ' + next1.x + ' ' + next1.y)
sleep(800)

// 4) Step2: 填三个输入框（dump 找 TextInput 坐标）
L = dump('w4')
ts = texts(L).join(' | ')
console.log('W4:', ts.substring(0, 500))
// TextInput 无 text——用 placeholder 定位难。策略: 依序点击 3 个输入框区域
// dump attributes 找 type=TextInput
let inputs = []
function walkIn(n) {
  if (!n) return
  if (n.attributes && (n.attributes.type === 'TextInput' || n.attributes.type === 'textinput')) {
    const b = (n.attributes.bounds || '').match(/[\d.]+/g) || []
    if (b.length >= 4) inputs.push({ x: Math.round((parseFloat(b[0]) + parseFloat(b[2])) / 2), y: Math.round((parseFloat(b[1]) + parseFloat(b[3])) / 2) })
  }
  ; (n.children || []).forEach(walkIn)
}
walkIn(L)
console.log('inputs found:', JSON.stringify(inputs))
if (inputs.length < 3) { console.error('FAIL: expected 3 TextInput, got ' + inputs.length); process.exit(1) }
// 输入域名
sh('uitest uiInput click ' + inputs[0].x + ' ' + inputs[0].y)
sleep(500)
sh('uitest uiInput input p53test.example.com')
sleep(500)
sh('uitest uiInput keyEvent 2072')  // ESC? no - use back via multi keyEvents? Tab to next
sh('uitest uiInput click ' + inputs[1].x + ' ' + inputs[1].y)
sleep(500)
sh('uitest uiInput input p53_session')
sleep(500)
sh('uitest uiInput click ' + inputs[2].x + ' ' + inputs[2].y)
sleep(500)
sh('uitest uiInput input p53_value_abc123')
sleep(500)
// 收起键盘
sh('uitest uiInput keyEvent 2')  // back
sleep(800)

// 5) 下一步 → Step3 预览
L = dump('w5')
const next2 = findBtn(L, '下一步')
if (!next2) { console.error('FAIL: no next after inputs'); process.exit(1) }
sh('uitest uiInput click ' + next2.x + ' ' + next2.y)
sleep(1000)

// 6) Step3 → 执行导入
L = dump('w6')
ts = texts(L).join(' | ')
console.log('W6(preview):', ts.substring(0, 500))
const exec = findBtn(L, '执行导入')
if (!exec) { console.error('FAIL: no 执行导入 btn'); process.exit(1) }
sh('uitest uiInput click ' + exec.x + ' ' + exec.y)
sleep(2500)

// 7) Step4 结果
L = dump('w7')
ts = texts(L).join(' | ')
console.log('W7(result):', ts.substring(0, 600))
console.log('E2E RESULT:', ts.includes('导入完成') ? 'PASS' : 'CHECK-MANUALLY')
