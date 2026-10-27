// 终版: 收键盘 → 下一步 → 执行 → 取证
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

let L = dump('q0')
let t = txts(L).join('|')
if (!t.includes('步骤 2')) { console.error('not step2:', t.substring(0, 120)); process.exit(1) }
// 收键盘: 点标题栏空白
sh('uitest uiInput click 640 60')
sleep(800)
// 重新选文件（确认选中态）+ 立即收键盘点下一步
L = dump('q1')
const fileItem = find(L, 'cookies.txt')
if (fileItem) { sh('uitest uiInput click ' + fileItem.x + ' ' + fileItem.y); sleep(600) }
sh('uitest uiInput click 640 30')   // 再点顶部
sleep(900)
L = dump('q2')
let next = find(L, '下一步')
console.log('next @', JSON.stringify(next), '(y应>650 若键盘已收)')
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(2500)
L = dump('q3')
t = txts(L).join('|')
console.log('AFTER NEXT:', t.substring(0, 220))
if (!t.includes('步骤 3') && !t.includes('预览完成')) {
  const log = sh('hilog -x')
  console.log((log || '').split(/\r?\n/).filter(l => /P53/.test(l)).slice(-6).join('\n'))
  process.exit(1)
}
const execBtn = find(L, '执行导入')
sh('uitest uiInput click ' + execBtn.x + ' ' + execBtn.y)
sleep(3500)
L = dump('q4')
const t2 = txts(L).join(' | ')
console.log('RESULT:', t2.substring(0, 450))
const log = sh('hilog -x')
const p53 = (log || '').split(/\r?\n/).filter(l => /P53|executeImport|parseNetscape|inject|imported|LOGIN_STATE_IMPORTED/.test(l)).slice(-22).join('\n')
console.log('---HILOG---\n' + (p53 || '(none)'))
fs.writeFileSync(EV + '/wizard_e2e_final_log.txt', p53 || '(none)')
console.log(t2.includes('导入完成') ? 'E2E PASS' : 'E2E FAIL')
