// P53: 向导 Step2 增加「沙盒路径直读」输入框（picker 之外的可靠兜底，filesDir 相对路径）
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

// 1. State 加 sandboxPath
rep("  private fileUri: string = ''\n  private fileText: string = ''",
    "  private fileUri: string = ''\n  private fileText: string = ''\n  @State sandboxPath: string = ''   // P53: filesDir 相对路径直读（picker 兜底）", 'state')

// 2. Step2 UI: 手动输入分支前加沙盒路径输入（所有文件来源通用）
rep("      if (this.sourceKind === ImportSourceKind.MANUAL) {\n        Text('手动录入 Cookie')",
    "      // P53: 沙盒路径直读（无 picker 环境的兜底：adb 预置 files/ 后填相对路径）\n      Text('或直接填写应用沙盒内路径 (files/ 下相对路径)')\n        .fontSize(13).fontColor(this.text2())\n        .margin({ top: 16, bottom: 6 })\n      TextInput({ placeholder: 'cookies.txt' })\n        .fontSize(14)\n        .onChange((v: string) => { this.sandboxPath = v })\n        .margin({ bottom: 6 })\n      if (this.sourceKind === ImportSourceKind.MANUAL) {\n        Text('手动录入 Cookie')", 'sandbox-ui')

// 3. 下一步按钮分流: 沙盒路径有值 → 直接读取解析
rep("                } else if (this.step === 2) {\n                  if (this.sourceKind === ImportSourceKind.MANUAL) {\n                    this.manualBuild()\n                  } else {\n                    this.pickFile()\n                  }\n                } else if (this.step === 3) {",
    "                } else if (this.step === 2) {\n                  if (this.sandboxPath.trim().length > 0) {\n                    this.loadFromSandbox()\n                  } else if (this.sourceKind === ImportSourceKind.MANUAL) {\n                    this.manualBuild()\n                  } else {\n                    this.pickFile()\n                  }\n                } else if (this.step === 3) {", 'next-branch')

// 4. loadFromSandbox 方法
rep("  // ---------- 手动输入构造单域 state ----------",
    "  // ---------- P53: 沙盒路径直读 ----------\n  private loadFromSandbox(): void {\n    const rel = this.sandboxPath.trim().replace(/^files\\//, '')\n    this.parseError = ''\n    const text = LoginStateManager.readSandboxText(rel)\n    if (text.length === 0) {\n      this.parseError = `沙盒文件读取失败或为空: files/${rel}`\n      return\n    }\n    this.fileText = text\n    this.pickedFileName = 'files/' + rel\n    this.parseAndPreview()\n  }\n\n  // ---------- 手动输入构造单域 state ----------", 'sandbox-method')

fs.writeFileSync(P, t, 'utf8')
console.log('ALL DONE')
