// P53 E2E v6: 从当前 Step2 续跑（输入框已有 cookies.txt）
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

let L = dump('h0')
const t0 = txts(L).join(' | ')
console.log('STATE:', t0.substring(0, 200))
let next = find(L, '下一步')
if (!next) { console.error('not at step2 with next; abort'); process.exit(1) }
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(1800)

L = dump('h1')
const t1 = txts(L)
console.log('PREVIEW:', t1.filter(t => /p53|域名|Cookie|条/.test(t)).slice(0, 12).join(' | '))
const exec = find(L, '执行导入')
if (!exec) { console.error('FAIL no exec. all:', t1.join(' | ').substring(0, 500)); process.exit(1) }
sh('uitest uiInput click ' + exec.x + ' ' + exec.y)
sleep(3200)

L = dump('h2')
const t2 = txts(L).join(' | ')
console.log('RESULT:', t2.substring(0, 500))

const log = sh('hilog -x')
const p53 = (log || '').split(/\r?\n/).filter(l => /P53|executeImport|parseNetscape|inject|imported/.test(l)).slice(-18).join('\n')
console.log('---HILOG---\n' + (p53 || '(none)'))
fs.writeFileSync(EV + '/wizard_e2e_v6_log.txt', p53 || '(none)')
console.log(t2.includes('导入完成') ? 'E2E PASS' : 'E2E FAIL')
