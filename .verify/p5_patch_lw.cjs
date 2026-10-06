// P5 real fix: tab item Row lacks layoutWeight — first tab's Text(layoutWeight(1))
// squeezes subsequent tabs to 4px. Give each tab item equal width.
const fs = require('fs');
const path = 'entry/src/main/ets/pages/BrowserShell.ets';
let s = fs.readFileSync(path, 'utf8');
const CRLF = s.includes('\r\n');
function must(c, l) { if (c !== 1) { console.error('ANCHOR FAIL: ' + l + ' matched ' + c); process.exit(1); } }

let a = `        .padding({ left: 8, right: 4 })
        .height(32)
        .borderRadius(4)
        .backgroundColor(tab.tabId === this.activeTabId ? '#E6F2FF' : '#FFFFFF')`;
let b = `        .padding({ left: 8, right: 4 })
        .height(32)
        .layoutWeight(1)
        .borderRadius(4)
        .backgroundColor(tab.tabId === this.activeTabId ? '#E6F2FF' : '#FFFFFF')`;
if (CRLF) { a = a.replace(/\n/g, '\r\n'); b = b.replace(/\n/g, '\r\n'); }
must(s.split(a).length - 1, 'tabitem');
s = s.replace(a, b);
fs.writeFileSync(path, s);
console.log('PATCHED layoutWeight OK');
