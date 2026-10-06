const fs = require('fs');
const path = 'entry/src/main/ets/pages/BrowserShell.ets';
let src = fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');

// ---- fix: tabsDirty force-rebuild pattern ----
const OLD1 = `  private pendingUrl: string = ''
  private pendingUrlTab: string = ''`;
const NEW1 = `  private pendingUrl: string = ''
  private pendingUrlTab: string = ''
  // P5: 覆盖态（NeoDashboard 前台）@State 赋值不驱动渲染；返回时需强制 ForEach 重建
  private tabsDirty: boolean = false`;
if (!src.includes(OLD1)) { throw new Error('field anchor not found'); }
src = src.replace(OLD1, NEW1);

const OLD2 = `  private syncFromTabManager(): void {
    try {
      const all = TabManager.getAllTabs()
      console.info('BrowserShell sync: managerTabs=' + all.length + ' uiTabs=' + this.tabs.length + ' active=' + TabManager.getActiveTabId())
      if (all.length !== this.tabs.length) {
        // ArkUI ForEach 差量失效兜底：先清空强制全量重建
        this.tabs = []
      }
      this.tabs = all`;
const NEW2 = `  private syncFromTabManager(): void {
    try {
      const all = TabManager.getAllTabs()
      console.info('BrowserShell sync: managerTabs=' + all.length + ' uiTabs=' + this.tabs.length + ' active=' + TabManager.getActiveTabId() + ' dirty=' + this.tabsDirty)
      if (this.tabsDirty) {
        // 覆盖态期间 tab 集合变化过：数据已更新但 UI 未渲染，ForEach diff 无变化
        // —— 必须先清空再赋值，强制全量重建
        this.tabs = []
        this.tabsDirty = false
      }
      this.tabs = all`;
if (!src.includes(OLD2)) { throw new Error('sync anchor not found'); }
src = src.replace(OLD2, NEW2);

const OLD3 = `      const allTabs = TabManager.getAllTabs()
      console.info('BrowserShell tab event: managerTabs=' + allTabs.length + ' uiTabs=' + this.tabs.length)
      this.tabs = allTabs`;
const NEW3 = `      const allTabs = TabManager.getAllTabs()
      if (allTabs.length !== this.tabs.length) {
        this.tabsDirty = true
      }
      console.info('BrowserShell tab event: managerTabs=' + allTabs.length + ' uiTabs=' + this.tabs.length + ' dirty=' + this.tabsDirty)
      this.tabs = allTabs`;
if (!src.includes(OLD3)) { throw new Error('event anchor not found'); }
src = src.replace(OLD3, NEW3);

fs.writeFileSync(path, src.replace(/\n/g, '\r\n'), 'utf8');
console.log('BrowserShell tabsDirty patched');
