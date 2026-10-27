// P53 E2E v4: 沙盒路径通道完整流
// 预置 cookies.txt (Netscape 双域) → 向导: 导入登录态→Netscape→下一步→沙盒路径输入 cookies.txt→下一步→预览→执行→结果+hilog
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
function nodes(layout) {
  const out = []
  function walk(n) { if (!n) return; if (n.attributes) out.push(n.attributes); (n.children || []).forEach(walk) }
  walk(layout)
  return out
}
function center(a) {
  const b = (a.bounds || '').match(/[\d.]+/g) || []
  if (b.length < 4) return null
  return { x: Math.round((parseFloat(b[0]) + parseFloat(b[2])) / 2), y: Math.round((parseFloat(b[1]) + parseFloat(b[3])) / 2) }
}
function find(L, label) {
  for (const a of nodes(L || {})) {
    if (a.text && a.text.includes(label)) { const c = center(a); if (c) return c }
  }
  return null
}
function txts(L) { return nodes(L || {}).filter(a => a.text).map(a => a.text) }

// ===== 预置测试文件 =====
// Netscape 格式: domain  flag  path  secure  expiry  name  value
const FUTURE = Math.floor(Date.now() / 1000) + 86400 * 30
const NETSCAPE = [
  '# Netscape HTTP Cookie File',
  '# https://curl.se/docs/http-cookies.html',
  '',
  '.p53a.example.com\tTRUE\t/\tFALSE\t' + FUTURE + '\tp53_session_a\tsessvalueAAA123',
  '.p53a.example.com\tTRUE\t/\tTRUE\t' + FUTURE + '\tp53_token_a\ttokenBBB456',
  '.p53b.example.org\tTRUE\t/\tFALSE\t' + FUTURE + '\tp53_session_b\tsessvalueCCC789',
  ''
].join('\n')
fs.writeFileSync(EV + '/cookies_fixture.txt', NETSCAPE, 'utf8')
// base64 推送（hdc file send Win 静默失败坑——base64 兜底）
const b64 = Buffer.from(NETSCAPE, 'utf8').toString('base64')
fs.writeFileSync(EV + '/cookies_b64.txt', b64, 'utf8')
execFileSync(HDC, ['-t', T, 'file', 'send', EV + '/cookies_b64.txt', '/data/local/tmp/p53_b64.txt'], { encoding: 'utf8' })
// app filesDir: /data/app/el2/100/base/com.browseros.kaihong/files (先探测)
let dir = sh('ls -d /data/app/el2/100/base/com.browseros.kaihong/files 2>/dev/null || ls -d /data/app/el2/100/com.browseros.kaihong/files 2>/dev/null || echo NOTFOUND')
console.log('filesDir probe:', dir.trim())
if (dir.includes('NOTFOUND')) {
  // 用 bm dump 查
  const bm = sh('bm dump -n com.browseros.kaihong | head -c 2000')
  console.log('bm dump head:', bm.substring(0, 300))
  process.exit(1)
}
const filesDir = dir.trim().split('\n')[0]
sh('echo ' + b64 + ' | base64 -d > ' + filesDir + '/cookies.txt')
const verify = sh('cat ' + filesDir + '/cookies.txt | head -4')
console.log('fixture preloaded:', verify.includes('Netscape') ? 'OK' : 'FAIL\n' + verify)

// ===== 向导流程 =====
sh('aa start -a EntryAbility -b com.browseros.kaihong')
sleep(2500)
let L = dump('f0')
let entry = find(L, '导入登录态')
if (!entry) { console.error('FAIL no entry'); process.exit(1) }
sh('uitest uiInput click ' + entry.x + ' ' + entry.y)
sleep(1600)

// Step1: Netscape 默认选中 → 下一步
L = dump('f1')
let next = find(L, '下一步')
if (!next) { console.error('FAIL step1 no next'); process.exit(1) }
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(900)

// Step2: 沙盒路径输入框（第 1 个 TextInput） inputText 坐标版
L = dump('f2')
const ti = nodes(L).filter(a => (a.type || '').toLowerCase() === 'textinput')
if (ti.length < 1) { console.error('FAIL no textinput'); process.exit(1) }
const c0 = center(ti[0])
console.log('sandbox input at', JSON.stringify(c0))
sh('uitest uiInput inputText ' + c0.x + ' ' + (c0.y - 4) + ' cookies.txt')
sleep(500)
// 收键盘
sh('uitest uiInput keyEvent 2')
sleep(600)
// 下一步 → 解析+预览
L = dump('f3')
next = find(L, '下一步')
if (!next) { console.error('FAIL step2 no next'); console.log('F3:', txts(L).join(' | ').substring(0, 300)); process.exit(1) }
sh('uitest uiInput click ' + next.x + ' ' + next.y)
sleep(1300)

// Step3: 预览
L = dump('f4')
const t4 = txts(L)
console.log('PREVIEW:', t4.filter(t => t.includes('p53') || t.includes('域名') || t.includes('Cookie')).slice(0, 10).join(' | '))
const exec = find(L, '执行导入')
if (!exec) { console.error('FAIL no exec btn'); console.log('F4 all:', t4.join(' | ').substring(0, 500)); process.exit(1) }
sh('uitest uiInput click ' + exec.x + ' ' + exec.y)
sleep(2800)

// Step4: 结果
L = dump('f5')
const t5 = txts(L).join(' | ')
console.log('RESULT:', t5.substring(0, 400))

// hilog
const log = sh('hilog -x')
const p53 = (log || '').split(/\r?\n/).filter(l => /P53|executeImport|parseNetscape/.test(l)).slice(-15).join('\n')
console.log('---HILOG---\n' + (p53 || '(none)'))
fs.writeFileSync(EV + '/wizard_e2e_v4_log.txt', p53 || '(none)')
console.log(t5.includes('导入完成') ? 'E2E PASS' : 'E2E FAIL')
