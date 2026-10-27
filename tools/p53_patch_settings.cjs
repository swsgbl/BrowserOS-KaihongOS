// P53: SettingsPage 加「导入向导」入口（CRLF 文件，node 补丁）
const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/SettingsPage.ets'
let t = fs.readFileSync(P, 'utf8')

// 1) 找到「已保存登录」行的 Text(I18n.t('stDomainN')...) 前插入向导入口
const anchor = "          Text(I18n.t('stDomainN').replace('{n}', '' + this.cntLogins))"
if (!t.includes(anchor)) { console.error('ANCHOR NOT FOUND: stDomainN line'); process.exit(1) }
const inject = `          // P53: 登录态导入向导入口\r\n` +
  `          Text('导入向导 →')\r\n` +
  `            .fontSize(11)\r\n` +
  `            .fontColor('#1A73E8')\r\n` +
  `            .padding({ left: 8, right: 8, top: 3, bottom: 3 })\r\n` +
  `            .borderRadius(4)\r\n` +
  `            .border({ width: 1, color: '#1A73E8' })\r\n` +
  `            .margin({ right: 6 })\r\n` +
  `            .onClick(() => { router.pushUrl({ url: 'pages/ImportWizardPage' }) })\r\n`
t = t.replace(anchor, inject + anchor)

fs.writeFileSync(P, t, 'utf8')
// verify
const v = fs.readFileSync(P, 'utf8')
if (!v.includes('pages/ImportWizardPage')) { console.error('VERIFY FAIL'); process.exit(1) }
console.log('OK: SettingsPage patched, ImportWizard entry added')
