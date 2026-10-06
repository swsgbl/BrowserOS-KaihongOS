const fs = require('fs');
const f = 'entry/src/main/ets/pages/BrowserShell.ets';
let c = fs.readFileSync(f, 'utf8');
const N = '\r\n';

// 1) 补 showNeo @State（上次锚点 CRLF 未匹配）
const anchor = "  @State showHistory: boolean = false";
if (!c.includes('showNeo: boolean')) {
  c = c.replace(anchor, anchor + N + "  // P6: NeoDashboard 内嵌覆盖层（不再 router.pushUrl，规避覆盖态不渲染）" + N + "  @State showNeo: boolean = false");
}

// 2) Builder 链 zIndex 改为 Stack 内直接包 Column（Builder 返回 void 不能链式）
c = c.replace("        if (this.showDashboard) {" + N + "          this.DashboardContent()" + N + "            .zIndex(20)" + N + "        }",
  "        if (this.showDashboard) {" + N + "          this.DashboardContent()" + N + "        }");
c = c.replace("          })" + N + "            .zIndex(30)" + N + "        }",
  "          })" + N + "        }");

fs.writeFileSync(f, c, 'utf8');
console.log('showNeo state:', c.includes('showNeo: boolean'), '| zIndex-chain removed:', !c.includes('.zIndex(20)') && !c.includes('.zIndex(30)'));
