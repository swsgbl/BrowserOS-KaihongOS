const fs = require('fs');
const path = 'entry/src/main/ets/pages/BrowserShell.ets';
let s = fs.readFileSync(path, 'utf8');
const old = "      if (this.showDashboard) {\r\n        this.DashboardContent()\r\n      } else {\r\n        this.WebViewContent()\r\n      }";
const neu = [
"      // P6 治本：Web 层常驻 —— 所有 tab 的 Web 组件始终挂载（非激活 Hidden 保活），",
"      // dashboard/NeoDashboard 作为覆盖层置顶。修复「dashboard 激活时全部 Web 销毁、",
"      // 覆盖态 ForEach 不新增」的时序缺口：agent tab 创建即有 WebView，BCP 立即可用。",
"      Stack() {",
"        this.WebViewContent()",
"        if (this.showDashboard) {",
"          this.DashboardContent()",
"            .zIndex(20)",
"        }",
"        if (this.showNeo) {",
"          NeoDashboardPanel({",
"            shellBack: () => {",
"              console.info('BrowserShell neo panel closed')",
"              this.showNeo = false",
"            },",
"            shellOpenReplay: (sessionId: string) => {",
"              console.info('BrowserShell open replay: ' + sessionId)",
"              this.showNeo = false",
"              const navParams: Record<string, Object> = { 'sessionId': sessionId }",
"              router.pushUrl({ url: 'pages/SessionPlayerPage', params: navParams })",
"            }",
"          })",
"            .zIndex(30)",
"        }",
"      }",
"      .layoutWeight(1)"
].join("\r\n");
if (!s.includes(old)) { console.error('OLD NOT FOUND'); process.exit(1); }
s = s.replace(old, neu);
// add showNeo state
const oldState = "  @State showHistory: boolean = false";
if (!s.includes("showNeo")) {
  s = s.replace(oldState, "  @State showHistory: boolean = false\r\n  // P6: NeoDashboard 内嵌覆盖层（不再 router.pushUrl，规避覆盖态不渲染）\r\n  @State showNeo: boolean = false");
}
// 查看代理按钮 → showNeo = true
s = s.replace("            console.info('BrowserShell navigate to NeoDashboardPage')\r\n            router.pushUrl({ url: 'pages/NeoDashboardPage' })",
  "            console.info('BrowserShell open NeoDashboard panel (in-shell overlay)')\r\n            this.showNeo = true");
// 导入登录态 诚实提示（B5）
s = s.replace("          .onClick(() => {\r\n          })\r\n      }\r\n      .margin({ top: 24 })",
  "          .onClick(() => {\r\n            AlertDialog.show({\r\n              title: '导入登录态',\r\n              message: 'KaihongOS 无 Chrome 浏览器数据可导入。请使用外部导出的 cookies.json（功能开发中）。',\r\n              primaryButton: { value: '知道了', action: () => { console.info('BrowserShell import-login acknowledged') } },\r\n              cancel: () => { console.info('BrowserShell import-login dismissed') }\r\n            })\r\n          })\r\n      }\r\n      .margin({ top: 24 })");
fs.writeFileSync(path, s, 'utf8');
console.log('OK BrowserShell patched, showNeo=' + s.includes('showNeo') + ' honestDialog=' + s.includes('cookies.json'));
