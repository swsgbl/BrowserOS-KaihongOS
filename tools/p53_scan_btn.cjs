// P53: Step2 加「扫描沙盒」按钮——零输入点选 files/ 下可导入文件（E2E 可驱动 + 实用兜底）
const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/ImportWizardPage.ets'
let t = fs.readFileSync(P, 'utf8')
function rep(oldStr, newStr, label) {
  const crlf = t.includes('\r\n')
  const o = crlf ? oldStr.replace(/\n/g, '\r\n') : oldStr
  const nw = crlf ? newStr.replace(/\n/g, '\r\n') : newStr
  if (!t.includes(o)) { console.error('MISS: ' + label); process.exit(1) }
  t = t.split(o).join(nw)
  console.log('OK:', label)
}

// 1. State: sandboxFiles 列表
rep("  @State sandboxPath: string = ''   // P53: filesDir 相对路径直读（picker 兜底）",
    "  @State sandboxPath: string = ''   // P53: filesDir 相对路径直读（picker 兜底）\n  @State sandboxFiles: string[] = []   // P53: 沙盒可导入文件扫描结果", 'state')

// 2. Step2 UI: 在沙盒路径输入框后加「扫描」按钮 + 文件列表
rep("      TextInput({ placeholder: 'cookies.txt' })\n        .fontSize(14)\n        .onChange((v: string) => { this.sandboxPath = v })\n        .margin({ bottom: 6 })",
    "      TextInput({ placeholder: 'cookies.txt' })\n        .fontSize(14)\n        .onChange((v: string) => { this.sandboxPath = v })\n        .margin({ bottom: 6 })\n      Button('扫描沙盒可导入文件')\n        .fontSize(13).fontColor(this.accent())\n        .backgroundColor(Color.Transparent)\n        .border({ width: 1, color: this.accent() })\n        .borderRadius(14)\n        .height(30)\n        .margin({ bottom: 6 })\n        .onClick(() => { this.scanSandbox() })\n      ForEach(this.sandboxFiles, (fname: string) => {\n        Text('📁 ' + fname)\n          .fontSize(14).fontColor(this.text())\n          .padding(10)\n          .width('100%')\n          .borderRadius(8)\n          .backgroundColor(this.card())\n          .border({ width: 1, color: this.sandboxPath === fname ? this.accent() : this.brd() })\n          .margin({ bottom: 6 })\n          .onClick(() => {\n            this.sandboxPath = fname\n            console.info('[P53] sandbox file selected: ' + fname)\n          })\n      })", 'scan-ui')

// 3. scanSandbox 方法
rep("  // ---------- P53: 沙盒路径直读 ----------",
    "  // ---------- P53: 扫描沙盒可导入文件（.txt/.json） ----------\n  private scanSandbox(): void {\n    const names = LoginStateManager.listSandboxImportable()\n    this.sandboxFiles = names\n    console.info('[P53] scanSandbox: found ' + names.length + ' files: ' + names.join(','))\n  }\n\n  // ---------- P53: 沙盒路径直读 ----------", 'scan-method')

fs.writeFileSync(P, t, 'utf8')
console.log('ALL DONE')
