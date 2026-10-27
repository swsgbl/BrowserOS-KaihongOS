// P53 E2E v7: 重装后完整流（重预置 fixture + 全流程）
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

// 0) 重新预置（重装 -r 保留数据，但以防万一）
const FUTURE = Math.floor(Date.now() / 1000) + 86400 * 30
const NETSCAPE = [
  '# Netscape HTTP Cookie File',
  '',
  '.p53a.example.com\tTRUE\t/\tFALSE\t' + FUTURE + '\tp53_session_a\tsessvalueAAA123',
  '.p53a.example.com\tTRUE\t/\tTRUE\t' + FUTURE + '\tp53_token_a\ttokenBBB456',
  '.p53b.example.org\tTRUE\t/\tFALSE\t' + FUTURE + '\tp53_session_b\tsessvalueCCC789', ''
].join('\n')
const b64 = Buffer.from(NETSCAPE, 'utf8').toString('base64')
execFileSync(HDC, ['-t', T, 'file', 'send', EV + '/cookies_b64.txt', '/data/local/tmp/p53_b64.txt'], { encoding: 'utf8' })
sh('echo ' + b64 + ' | base64 -d > /data/app/el2/100/base/com.browseros.kaihong/files/cookies.txt')
console.log('fixture:', sh('head -1 /data/app/el2/100/base/com.browseros.kaihong/files/cookies.txt').trim())

sh('aa start -a EntryAbility -b com.browseros.kaihong')
sleep(2500)
let L = dump('k0')
let entry = find(L, '导入登录态')
if (!entry) { console.error('FAIL entry', txts(L).slice(0, 15).join('|')); process.exit(1) }
sh('uitest uiInput click ' + entry.x + ' ' + entry.y)
sleep(1600)

L = dump('k1')
let next = find(L, '下一步')
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(900)

L = dump('k2')
const ti = nodes(L).filter(a => (a.type || '').toLowerCase() === 'textinput')
const c0 = center(ti[0])
sh('uitest uiInput inputText ' + c0.x + ' ' + c0.y + ' cookies.txt')
sleep(500)
sh('uitest uiInput click 640 60')
sleep(700)
L = dump('k2b')
console.log('path filled:', txts(L).includes('cookies.txt') ? 'yes' : 'NO')
next = find(L, '下一步')
if (!next) { console.error('FAIL next hidden'); process.exit(1) }
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(1800)

L = dump('k3')
const t3 = txts(L)
console.log('PREVIEW:', t3.filter(t => /p53|域名|Cookie|条/.test(t)).slice(0, 12).join(' | '))
const exec = find(L, '执行导入')
if (!exec) { console.error('FAIL no exec. all:', t3.join(' | ').substring(0, 400)); sh('hilog -x > /dev/null'); process.exit(1) }
sh('uitest uiInput click ' + exec.x + ' ' + exec.y)
sleep(3200)

L = dump('k4')
const t4 = txts(L).join(' | ')
console.log('RESULT:', t4.substring(0, 500))

const log = sh('hilog -x')
const p53 = (log || '').split(/\r?\n/).filter(l => /P53|executeImport|parseNetscape|inject|imported|readSandbox/.test(l)).slice(-20).join('\n')
console.log('---HILOG---\n' + (p53 || '(none)'))
fs.writeFileSync(EV + '/wizard_e2e_v7_log.txt', p53 || '(none)')
console.log(t4.includes('导入完成') ? 'E2E PASS' : 'E2E FAIL')
