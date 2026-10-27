// P53 E2E v8: 焦点版文本注入（click 聚焦 → uiInput text）
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

// 当前应停在 Step2（上次 k2b 状态）。dump 确认
let L = dump('m0')
const t0 = txts(L).join(' | ')
console.log('STATE:', t0.substring(0, 150))
if (!t0.includes('步骤 2')) {
  // 从头走
  sh('aa start -a EntryAbility -b com.browseros.kaihong'); sleep(2500)
  L = dump('m0r')
  const e = find(L, '导入登录态'); sh('uitest uiInput click ' + e.x + ' ' + e.y); sleep(1600)
  L = dump('m0s')
  const n = find(L, '下一步'); sh('uitest uiInput click ' + n.x + ' ' + n.y); sleep(900)
  L = dump('m0t')
}
// 清掉旧值: 全选删除
const ti = nodes(L).filter(a => (a.type || '').toLowerCase() === 'textinput')
const c0 = center(ti[0])
sh('uitest uiInput click ' + c0.x + ' ' + c0.y)
sleep(600)
// Ctrl+A (2072? 用组合键码) —— uitest keyEvent 支持 id 对:  IKB 是 ctrl=2072, A=2017? 简化: 连续退格
for (let i = 0; i < 14; i++) sh('uitest uiInput keyEvent 67')
sleep(400)
sh('uitest uiInput text cookies.txt')
sleep(700)
sh('uitest uiInput click 640 60')
sleep(800)
L = dump('m1')
console.log('after text:', txts(L).filter(t => t === 'cookies.txt' || t.includes('cookies')).join('|') || '(no cookies text)')
const next = find(L, '下一步')
if (!next) { console.error('FAIL next'); process.exit(1) }
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(2000)

L = dump('m2')
const t2 = txts(L)
console.log('AFTER NEXT:', t2.filter(t => /p53|域名|Cookie|步骤|预览|执行/.test(t)).slice(0, 12).join(' | '))
const exec = find(L, '执行导入')
if (!exec) {
  const log = sh('hilog -x')
  const p53 = (log || '').split(/\r?\n/).filter(l => /P53|readSandbox|readText|parseNetscape|parseAny/.test(l)).slice(-8).join('\n')
  console.log('HILOG:', p53 || '(none)')
  console.error('FAIL no exec')
  process.exit(1)
}
sh('uitest uiInput click ' + exec.x + ' ' + exec.y)
sleep(3200)
L = dump('m3')
const t3 = txts(L).join(' | ')
console.log('RESULT:', t3.substring(0, 500))
const log = sh('hilog -x')
const p53 = (log || '').split(/\r?\n/).filter(l => /P53|executeImport|parseNetscape|inject|imported|readSandbox/.test(l)).slice(-20).join('\n')
console.log('---HILOG---\n' + (p53 || '(none)'))
fs.writeFileSync(EV + '/wizard_e2e_v8_log.txt', p53 || '(none)')
console.log(t3.includes('导入完成') ? 'E2E PASS' : 'E2E FAIL')
