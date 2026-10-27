// 收尾: 从 Step2 已选定 cookies.txt 状态点下一步（重试2次）
const { execFileSync } = require('child_process')
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe'
const T = '192.168.161.137:10178'
const fs = require('fs')
const EV = 'D:/BrowserOS - KaihongOS/evidence/p53'
function sh(cmd) { try { return execFileSync(HDC, ['-t', T, 'shell', cmd], { encoding: 'utf8', timeout: 30000 }) } catch (e) { return (e.stdout || '') + (e.stderr || '') } }
function sleep(ms) { execFileSync('ping', ['-n', String(Math.floor(ms / 1000) + 1), '127.0.0.1'], { stdio: 'ignore' }) }
function dump(name) {
  sh('uitest dumpLayout -p /data/local/tmp/' + name + '.json')
  try { execFileSync(HDC, ['-t', T, 'file', 'recv', '/data/local/tmp/' + name + '.json', 'D:\\BrowserOS - KaihongOS\\evidence\\p53\\' + name + '.json'], { encoding: 'utf8' }) } catch (e) { }
  try { return JSON.parse(fs.readFileSync(EV + '/' + name + '.json', 'utf8')) } catch (e) { return null }
}
function nodes(L) { const o = []; (function w(n) { if (!n) return; if (n.attributes) o.push(n.attributes); (n.children || []).forEach(w) })(L || {}); return o }
function center(a) { const b = (a.bounds || '').match(/[\d.]+/g) || []; return b.length < 4 ? null : { x: Math.round((+b[0] + +b[2]) / 2), y: Math.round((+b[1] + +b[3]) / 2) } }
function find(L, label) { for (const a of nodes(L)) { if (a.text && a.text.includes(label)) { const c = center(a); if (c) return c } } return null }
function txts(L) { return nodes(L).filter(a => a.text).map(a => a.text) }

let L = dump('w0')
let t = txts(L).join('|')
if (!t.includes('步骤 2')) { console.error('not at step2:', t.substring(0, 150)); process.exit(1) }
let next = find(L, '下一步')
console.log('next btn @', JSON.stringify(next))
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(1500)
sh('uitest uiInput click ' + next.x + ' ' + next.y)  // 二次保险
sleep(2500)
L = dump('w1')
t = txts(L).join('|')
console.log('AFTER:', t.substring(0, 250))
if (!t.includes('步骤 3')) {
  const log = sh('hilog -x')
  const p53 = (log || '').split(/\r?\n/).filter(l => /P53|readSandbox|parseNetscape|readText/.test(l)).slice(-8).join('\n')
  console.log('HILOG:', p53)
  process.exit(1)
}
// Step3 → 执行
const execBtn = find(L, '执行导入')
if (!execBtn) { console.error('no exec at step3'); process.exit(1) }
sh('uitest uiInput click ' + execBtn.x + ' ' + execBtn.y)
sleep(3500)
L = dump('w2')
const t2 = txts(L).join(' | ')
console.log('RESULT:', t2.substring(0, 450))
const log = sh('hilog -x')
const p53 = (log || '').split(/\r?\n/).filter(l => /P53|executeImport|parseNetscape|inject|imported|LOGIN_STATE_IMPORTED/.test(l)).slice(-22).join('\n')
console.log('---HILOG---\n' + (p53 || '(none)'))
fs.writeFileSync(EV + '/wizard_e2e_final_log.txt', p53 || '(none)')
console.log(t2.includes('导入完成') ? 'E2E PASS' : 'E2E FAIL')
