/* fix p47CreateIncognitoTab: use TabManager.getAllTabs() */
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/BrowserShell.ets';
let s = fs.readFileSync(P, 'utf8');
const eol = s.includes('\r\n') ? '\r\n' : '\n';
s = s.replace(/\r\n/g, '\n');
const o = "    this.p47IncognitoTabs.add(tab.tabId)\n    this.tabs = TabManager.getTabs()\n    this.activeTabId = tab.tabId";
const n = "    this.p47IncognitoTabs.add(tab.tabId)\n    this.tabs = TabManager.getAllTabs()\n    this.activeTabId = tab.tabId";
if (!s.includes(o)) { console.log('MISS'); process.exit(1); }
s = s.replace(o, n);
fs.writeFileSync(P, eol === '\r\n' ? s.replace(/\n/g, '\r\n') : s, 'utf8');
console.log('fixed getAllTabs');
