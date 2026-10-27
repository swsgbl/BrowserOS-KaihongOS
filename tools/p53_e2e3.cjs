// P53 E2E v3: 直接点「导入登录态」(V0 可见) → 向导流程
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
      if (c) return { ...c, text: a.text, type: a.type }
    }
  }
  return null
}
function txts(L) { return nodes(L || { attributes: {}, children: [] }).filter(a => a.text).map(a => a.text) }

// 0) 拉前台
sh('aa start -a EntryAbility -b com.browseros.kaihong')
sleep(2500)
let L = dump('e0')
const entry = findByText(L, '导入登录态')
if (!entry) { console.error('FAIL: no 导入登录态 entry'); console.log(txts(L).slice(0, 40).join(' | ')); process.exit(1) }
console.log('STEP0: click 导入登录态 @', entry.x, entry.y)
sh('uitest uiInput click ' + entry.x + ' ' + entry.y)
sleep(1800)

// 1) 向导 Step1
L = dump('e1')
console.log('S1:', txts(L).slice(0, 25).join(' | '))
const manual = findByText(L, '手动输入')
if (!manual) { console.error('FAIL: no manual option'); process.exit(1) }
sh('uitest uiInput click ' + manual.x + ' ' + manual.y)
sleep(600)
L = dump('e1b')
const n1 = findByText(L, '下一步')
if (!n1) { console.error('FAIL: no next btn'); process.exit(1) }
sh('uitest uiInput click ' + n1.x + ' ' + n1.y)
sleep(900)

// 2) Step2 输入
L = dump('e2')
const inputs = nodes(L).filter(a => (a.type || '').toLowerCase() === 'textinput').map(a => center(a)).filter(Boolean)
console.log('S2 inputs:', JSON.stringify(inputs))
if (inputs.length < 3) { console.error('FAIL: inputs=' + inputs.length); process.exit(1) }
sh('uitest uiInput click ' + inputs[0].x + ' ' + inputs[0].y); sleep(450)
sh('uitest uiInput input p53test.example.com'); sleep(450)
sh('uitest uiInput click ' + inputs[1].x + ' ' + inputs[1].y); sleep(450)
sh('uitest uiInput input p53_session'); sleep(450)
sh('uitest uiInput click ' + inputs[2].x + ' ' + inputs[2].y); sleep(450)
sh('uitest uiInput input p53_value_abc123'); sleep(450)
sh('uitest uiInput keyEvent 2'); sleep(700)

// 3) 下一步 → 预览
L = dump('e3')
const n2 = findByText(L, '下一步')
if (!n2) { console.error('FAIL: no next2'); console.log('E3:', txts(L).join(' | ').substring(0, 400)); process.exit(1) }
sh('uitest uiInput click ' + n2.x + ' ' + n2.y)
sleep(1100)

// 4) 预览 → 执行导入
L = dump('e4')
console.log('S3 preview:', txts(L).slice(0, 15).join(' | '))
const exec = findByText(L, '执行导入')
if (!exec) { console.error('FAIL: no exec'); process.exit(1) }
sh('uitest uiInput click ' + exec.x + ' ' + exec.y)
sleep(2800)

// 5) 结果
L = dump('e5')
const t5 = txts(L).join(' | ')
console.log('S4 result:', t5.substring(0, 400))
const pass = t5.includes('导入完成')
console.log(pass ? 'WIZARD E2E PASS' : 'WIZARD E2E FAIL')

// 6) hilog 取证 P53
const log = sh('hilog -x | grep P53')
console.log('HILOG P53 lines:', (log || '').split(/\r?\n/).filter(l => l.includes('P53')).slice(-12).join('\n') || '(none)')
fs.writeFileSync(EV + '/wizard_e2e_log.txt', log || '(no P53 logs)')
