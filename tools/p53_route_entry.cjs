// P53: 旧「导入登录态」按钮改跳新向导页
const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/BrowserShell.ets'
let t = fs.readFileSync(P, 'utf8')
const old = "  private importLoginState(): void {\r\n" +
  "    this.importPath = ''\r\n" +
  "    this.importResult = ''\r\n" +
  "    this.showImportPanel = true\r\n" +
  "  }"
const nw = "  private importLoginState(): void {\r\n" +
  "    // P53: 升级为四步导入向导（来源选择→文件选择→预览→执行注入）\r\n" +
  "    router.pushUrl({ url: 'pages/ImportWizardPage' })\r\n" +
  "  }"
if (!t.includes(old)) { console.error('MISS importLoginState'); process.exit(1) }
t = t.replace(old, nw)
fs.writeFileSync(P, t, 'utf8')
if (!fs.readFileSync(P, 'utf8').includes("router.pushUrl({ url: 'pages/ImportWizardPage' })")) { console.error('VERIFY FAIL'); process.exit(1) }
console.log('OK: importLoginState -> ImportWizardPage')
