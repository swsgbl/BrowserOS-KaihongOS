// P53 E2E v5: 修复键盘遮挡——inputText 后点标题栏收键盘
const { execFileSync } = require('child_process')
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe'
const T = '192.168.161.137:10178'
const fs = require('fs')
const EV = 'D:/BrowserOS - KaihongOS/evidence/p53'

function sh(cmd) {
  try { return execFileSync(HDC, ['-t', T, 'shell', cmd], { encoding: 'utf8', timeout: 30000 }) }
  catch (e) { return (e.stdout || '') + (e.stderr || '') }
}
function sleep(ms) { execFileSync('ping', ['-n', String(Math.floor(ms / 1000) + 1), '127.0.0.1'], { stdio: 'ignore' }) }
function dump(name) {
  sh('uitest dumpLayout -p /data/local/tmp/' + name + '.json')
  try { execFileSync(HDC, ['-t', T, 'file', 'recv', '/data/local/tmp/' + name + '.json', 'D:\\BrowserOS - KaihongOS\\evidence\\p53\\' + name + '.json'], { encoding: 'utf8' }) } catch (e) { }
  try { return JSON.parse(fs.readFileSync(EV + '/' + name + '.json', 'utf8')) } catch (e) { console.error('dump-parse-fail', name); return null }
}
function nodes(L) { const o = []; (function w(n) { if (!n) return; if (n.attributes) o.push(n.attributes); (n.children || []).forEach(w) })(L || {}); return o }
function center(a) { const b = (a.bounds || '').match(/[\d.]+/g) || []; return b.length < 4 ? null : { x: Math.round((+b[0] + +b[2]) / 2), y: Math.round((+b[1] + +b[3]) / 2) } }
function find(L, label) { for (const a of nodes(L)) { if (a.text && a.text.includes(label)) { const c = center(a); if (c) return c } } return null }
function txts(L) { return nodes(L).filter(a => a.text).map(a => a.text) }

// 0) 确认 fixture 还在
const v = sh('head -2 /data/app/el2/100/base/com.browseros.kaihong/files/cookies.txt')
if (!v.includes('Netscape')) { console.error('fixture missing'); process.exit(1) }

sh('aa start -a EntryAbility -b com.browseros.kaihong')
sleep(2500)
let L = dump('g0')
const entry = find(L, '导入登录态')
if (!entry) { console.error('FAIL entry'); process.exit(1) }
sh('uitest uiInput click ' + entry.x + ' ' + entry.y)
sleep(1600)

// Step1 下一步
L = dump('g1')
let next = find(L, '下一步')
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(900)

// Step2: 输入沙盒路径（先点输入框聚焦）
L = dump('g2')
const ti = nodes(L).filter(a => (a.type || '').toLowerCase() === 'textinput')
const c0 = center(ti[0])
sh('uitest uiInput click ' + c0.x + ' ' + c0.y)
sleep(500)
sh('uitest uiInput text cookies.txt')
sleep(500)
// 点标题收键盘
sh('uitest uiInput click 640 60')
sleep(700)
L = dump('g2b')
const hasVal = txts(L).some(t => t.includes('cookies.txt'))
console.log('sandbox path filled:', hasVal ? 'yes' : 'NO')
next = find(L, '下一步')
if (!next) { console.error('FAIL next hidden after kb'); process.exit(1) }
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(1500)

// Step3
L = dump('g3')
const t3 = txts(L)
console.log('PREVIEW:', t3.filter(t => /p53|域名|Cookie|条/.test(t)).slice(0, 12).join(' | '))
const exec = find(L, '执行导入')
if (!exec) { console.error('FAIL no exec. all:', t3.join(' | ').substring(0, 400)); process.exit(1) }
sh('uitest uiInput click ' + exec.x + ' ' + exec.y)
sleep(3000)

// Step4
L = dump('g4')
const t4 = txts(L).join(' | ')
console.log('RESULT:', t4.substring(0, 400))

// hilog 取证
const log = sh('hilog -x')
const p53 = (log || '').split(/\r?\n/).filter(l => /P53|executeImport|parseNetscape|injectDomain|imported/.test(l)).slice(-15).join('\n')
console.log('---HILOG---\n' + (p53 || '(none)'))
fs.writeFileSync(EV + '/wizard_e2e_v5_log.txt', p53 || '(none)')
console.log(t4.includes('导入完成') ? 'E2E PASS' : 'E2E FAIL')
