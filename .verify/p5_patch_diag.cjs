const fs = require('fs');
const path = 'entry/src/main/ets/pages/BrowserShell.ets';
let src = fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');

// ---- diag + force ForEach rebuild in syncFromTabManager ----
const OLD = `  private syncFromTabManager(): void {
    try {
      this.tabs = TabManager.getAllTabs()`;
const NEW = `  private syncFromTabManager(): void {
    try {
      const all = TabManager.getAllTabs()
      console.info('BrowserShell sync: managerTabs=' + all.length + ' uiTabs=' + this.tabs.length + ' active=' + TabManager.getActiveTabId())
      if (all.length !== this.tabs.length) {
        // ArkUI ForEach 差量失效兜底：先清空强制全量重建
        this.tabs = []
      }
      this.tabs = all`;
if (!src.includes(OLD)) { throw new Error('sync anchor not found'); }
src = src.replace(OLD, NEW);

const OLD2 = `      this.tabs = TabManager.getAllTabs()
      const activeId = TabManager.getActiveTabId()
      if (activeId.length > 0 && activeId !== this.activeTabId) {`;
const NEW2 = `      const allTabs = TabManager.getAllTabs()
      console.info('BrowserShell tab event: managerTabs=' + allTabs.length + ' uiTabs=' + this.tabs.length)
      this.tabs = allTabs
      const activeId = TabManager.getActiveTabId()
      if (activeId.length > 0 && activeId !== this.activeTabId) {`;
if (!src.includes(OLD2)) { throw new Error('event anchor not found'); }
src = src.replace(OLD2, NEW2);

fs.writeFileSync(path, src.replace(/\n/g, '\r\n'), 'utf8');
console.log('BrowserShell diag patched');
