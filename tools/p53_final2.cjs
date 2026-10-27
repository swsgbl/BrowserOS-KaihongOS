// 最终收敛: fixture + E2E 一次跑完
const { execFileSync } = require('child_process')
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe'
const T = '192.168.161.137:10178'
const fs = require('fs')
const EV = 'D:/BrowserOS - KaihongOS/evidence/p53'
function sh(cmd) { try { return execFileSync(HDC, ['-t', T, 'shell', cmd], { encoding: 'utf8', timeout: 30000 }) } catch (e) { return (e.stdout || '') + (e.stderr || '') } }
function sleep(ms) { execFileSync('ping', ['-n', String(Math.floor(ms / 1000) + 1), '127.0.0.1'], { stdio: 'ignore' }) }
const FD = '/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files'

// 用 printf 写（Tab=$'\t' 不可用，用 printf %s+显式\t）
const FUT = Math.floor(Date.now() / 1000) + 2592000
const line = (d, n, v, sec) => d + '\\tTRUE\\t/\\t' + (sec ? 'TRUE' : 'FALSE') + '\\t' + FUT + '\\t' + n + '\\t' + v
const cmd = 'printf \'' +
  '# Netscape HTTP Cookie File\\n' +
  '\\n' +
  line('.p53a.example.com', 'p53_session_a', 'sessvalueAAA123', false) + '\\n' +
  line('.p53a.example.com', 'p53_token_a', 'tokenBBB456', true) + '\\n' +
  line('.p53b.example.org', 'p53_session_b', 'sessvalueCCC789', false) + '\\n' +
  '\' > ' + FD + '/cookies.txt && cat ' + FD + '/cookies.txt'
const out = sh(cmd)
console.log('fixture:', out.includes('p53_session_a') ? 'OK' : 'FAIL\n' + out.substring(0, 300))
if (!out.includes('p53_session_a')) process.exit(1)

function dump(name) {
  sh('uitest dumpLayout -p /data/local/tmp/' + name + '.json')
  try { execFileSync(HDC, ['-t', T, 'file', 'recv', '/data/local/tmp/' + name + '.json', 'D:\\BrowserOS - KaihongOS\\evidence\\p53\\' + name + '.json'], { encoding: 'utf8' }) } catch (e) { }
  try { return JSON.parse(fs.readFileSync(EV + '/' + name + '.json', 'utf8')) } catch (e) { return null }
}
function nodes(L) { const o = []; (function w(n) { if (!n) return; if (n.attributes) o.push(n.attributes); (n.children || []).forEach(w) })(L || {}); return o }
function center(a) { const b = (a.bounds || '').match(/[\d.]+/g) || []; return b.length < 4 ? null : { x: Math.round((+b[0] + +b[2]) / 2), y: Math.round((+b[1] + +b[3]) / 2) } }
function find(L, label) { for (const a of nodes(L)) { if (a.text && a.text.includes(label)) { const c = center(a); if (c) return c } } return null }
function txts(L) { return nodes(L).filter(a => a.text).map(a => a.text) }

// 从当前状态驱动（可能在向导 Step2）——先 force-stop 重来
sh('aa force-stop com.browseros.kaihong')
sleep(1200)
sh('aa start -a EntryAbility -b com.browseros.kaihong')
sleep(2500)
let L = dump('y0')
const t0 = txts(L).join(' | ')
console.log('START:', t0.substring(0, 120))
const entry = find(L, '导入登录态')
if (entry) {
  sh('uitest uiInput click ' + entry.x + ' ' + entry.y)
  sleep(1500)
  L = dump('y1')
  const next = find(L, '下一步')
  sh('uitest uiInput click ' + next.x + ' ' + next.y)
  sleep(900)
  L = dump('y2')
}
// Step2
const scan = find(L, '扫描沙盒')
if (!scan) { console.error('not at step2:', txts(L).join('|').substring(0, 200)); process.exit(1) }
sh('uitest uiInput click ' + scan.x + ' ' + scan.y)
sleep(1000)
L = dump('y3')
console.log('scan list:', txts(L).filter(x => x.startsWith('📁')).join(' | '))
const fileItem = find(L, 'cookies.txt')
if (!fileItem) { console.error('FAIL no cookies.txt'); process.exit(1) }
sh('uitest uiInput click ' + fileItem.x + ' ' + fileItem.y)
sleep(700)
L = dump('y4')
let next = find(L, '下一步')
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(2200)

L = dump('y5')
const t5 = txts(L)
console.log('PREVIEW:', t5.filter(t => /p53|域名|Cookie|条|步骤 3/.test(t)).slice(0, 14).join(' | '))
const execBtn = find(L, '执行导入')
if (!execBtn) { console.error('FAIL no exec:', t5.join('|').substring(0, 300)); process.exit(1) }
sh('uitest uiInput click ' + execBtn.x + ' ' + execBtn.y)
sleep(3500)

L = dump('y6')
const t6 = txts(L).join(' | ')
console.log('RESULT:', t6.substring(0, 450))
const log = sh('hilog -x')
const p53 = (log || '').split(/\r?\n/).filter(l => /P53|executeImport|parseNetscape|inject|imported|readSandbox|scanSandbox|LOGIN_STATE/.test(l)).slice(-22).join('\n')
console.log('---HILOG---\n' + (p53 || '(none)'))
fs.writeFileSync(EV + '/wizard_e2e_final_log.txt', p53 || '(none)')
console.log(t6.includes('导入完成') ? 'E2E PASS' : 'E2E FAIL')
