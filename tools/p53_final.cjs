// 收敛: fixture 推到 app 真实 filesDir + 最后一次 E2E
const { execFileSync } = require('child_process')
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe'
const T = '192.168.161.137:10178'
const fs = require('fs')
const EV = 'D:/BrowserOS - KaihongOS/evidence/p53'
function sh(cmd) { try { return execFileSync(HDC, ['-t', T, 'shell', cmd], { encoding: 'utf8', timeout: 30000 }) } catch (e) { return (e.stdout || '') + (e.stderr || '') } }
function sleep(ms) { execFileSync('ping', ['-n', String(Math.floor(ms / 1000) + 1), '127.0.0.1'], { stdio: 'ignore' }) }
const FD = '/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files'
// push fixture
sh('cat /data/local/tmp/p53_b64.txt | base64 -d > ' + FD + '/cookies.txt')
const head = sh('cat ' + FD + '/cookies.txt')
console.log('fixture in app filesDir:', head.includes('Netscape') ? 'OK' : 'FAIL')

function dump(name) {
  sh('uitest dumpLayout -p /data/local/tmp/' + name + '.json')
  try { execFileSync(HDC, ['-t', T, 'file', 'recv', '/data/local/tmp/' + name + '.json', 'D:\\BrowserOS - KaihongOS\\evidence\\p53\\' + name + '.json'], { encoding: 'utf8' }) } catch (e) { }
  try { return JSON.parse(fs.readFileSync(EV + '/' + name + '.json', 'utf8')) } catch (e) { return null }
}
function nodes(L) { const o = []; (function w(n) { if (!n) return; if (n.attributes) o.push(n.attributes); (n.children || []).forEach(w) })(L || {}); return o }
function center(a) { const b = (a.bounds || '').match(/[\d.]+/g) || []; return b.length < 4 ? null : { x: Math.round((+b[0] + +b[2]) / 2), y: Math.round((+b[1] + +b[3]) / 2) } }
function find(L, label) { for (const a of nodes(L)) { if (a.text && a.text.includes(label)) { const c = center(a); if (c) return c } } return null }
function txts(L) { return nodes(L).filter(a => a.text).map(a => a.text) }

sh('aa start -a EntryAbility -b com.browseros.kaihong')
sleep(2500)
let L = dump('z0')
const entry = find(L, '导入登录态')
if (!entry) { console.error('no entry'); process.exit(1) }
sh('uitest uiInput click ' + entry.x + ' ' + entry.y)
sleep(1500)
L = dump('z1')
let next = find(L, '下一步')
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(900)
L = dump('z2')
const scan = find(L, '扫描沙盒')
sh('uitest uiInput click ' + scan.x + ' ' + scan.y)
sleep(900)
L = dump('z3')
const t3 = txts(L)
console.log('scan list:', t3.filter(x => x.startsWith('📁')).join(' | ') || '(empty)')
const fileItem = find(L, 'cookies.txt')
if (!fileItem) { console.error('FAIL cookies.txt not listed'); process.exit(1) }
sh('uitest uiInput click ' + fileItem.x + ' ' + fileItem.y)
sleep(600)
L = dump('z4')
next = find(L, '下一步')
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(2000)

L = dump('z5')
const t5 = txts(L)
console.log('PREVIEW:', t5.filter(t => /p53|域名|Cookie|条|步骤 3/.test(t)).slice(0, 12).join(' | '))
const execBtn = find(L, '执行导入')
if (!execBtn) { console.error('FAIL no exec. all:', t5.join(' | ').substring(0, 400)); process.exit(1) }
sh('uitest uiInput click ' + execBtn.x + ' execBtn.y'.replace('execBtn.y', execBtn.y))
sleep(3200)

L = dump('z6')
const t6 = txts(L).join(' | ')
console.log('RESULT:', t6.substring(0, 450))
const log = sh('hilog -x')
const p53 = (log || '').split(/\r?\n/).filter(l => /P53|executeImport|parseNetscape|inject|imported|readSandbox|scanSandbox/.test(l)).slice(-20).join('\n')
console.log('---HILOG---\n' + (p53 || '(none)'))
fs.writeFileSync(EV + '/wizard_e2e_final_log.txt', p53 || '(none)')
console.log(t6.includes('导入完成') ? 'E2E PASS' : 'E2E FAIL')
