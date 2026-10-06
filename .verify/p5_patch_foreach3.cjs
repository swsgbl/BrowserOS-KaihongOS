// P5 fix part3: re-apply patch1 (two-phase rebuild) + patch2 (covering->dirty)
const fs = require('fs');
const path = 'entry/src/main/ets/pages/BrowserShell.ets';
let s = fs.readFileSync(path, 'utf8');
const CRLF = s.includes('\r\n');
function must(c, l) { if (c !== 1) { console.error('ANCHOR FAIL: ' + l + ' matched ' + c); process.exit(1); } }

let a1 = `      if (this.tabsDirty) {
        // 覆盖态期间 tab 集合变化过：数据已更新但 UI 未渲染，ForEach diff 无变化
        // —— 必须先清空再赋值，强制全量重建
        this.tabs = []
        this.tabsDirty = false
      }
      this.tabs = all`;
let b1 = `      if (this.tabsDirty) {
        // 覆盖态期间 tab 集合变化过：同帧 []→all 两次赋值被 ArkUI 批合并，
        // ForEach 子树未销毁。必须两帧：本帧清空销毁，下一帧全量重建
        this.tabs = []
        this.tabsDirty = false
        setTimeout(() => {
          this.tabs = TabManager.getAllTabs()
          const activeId2 = TabManager.getActiveTabId()
          if (activeId2.length > 0) {
            this.activeTabId = activeId2
          }
          console.info('BrowserShell rebuild tabs next frame: ' + this.tabs.length)
        }, 0)
        return
      }
      this.tabs = all`;
if (CRLF) { a1 = a1.replace(/\n/g, '\r\n'); b1 = b1.replace(/\n/g, '\r\n'); }
must(s.split(a1).length - 1, 'patch1');
s = s.replace(a1, b1);

let a2 = `      const allTabs = TabManager.getAllTabs()
      if (allTabs.length !== this.tabs.length) {
        this.tabsDirty = true
      }`;
let b2 = `      const allTabs = TabManager.getAllTabs()
      if (allTabs.length !== this.tabs.length) {
        this.tabsDirty = true
      }
      // P5: 覆盖态（NeoDashboardPage 前台）期间 BrowserShell @State 赋值不驱动渲染，
      // 标记 dirty 让 onPageShow 返回时强制两帧重建
      if (this.covering) this.tabsDirty = true`;
if (CRLF) { a2 = a2.replace(/\n/g, '\r\n'); b2 = b2.replace(/\n/g, '\r\n'); }
must(s.split(a2).length - 1, 'patch2');
s = s.replace(a2, b2);

fs.writeFileSync(path, s);
console.log('PATCHED part3 OK');
