// P5 fix part2: covering flag (tabsDirty is private, not @State)
const fs = require('fs');
const path = 'entry/src/main/ets/pages/BrowserShell.ets';
let s = fs.readFileSync(path, 'utf8');
const CRLF = s.includes('\r\n');
function must(c, l) { if (c !== 1) { console.error('ANCHOR FAIL: ' + l + ' matched ' + c); process.exit(1); } }

let a3 = `  private tabsDirty: boolean = false`;
let b3 = `  private tabsDirty: boolean = false
  /** P5: 覆盖态标记 —— NeoDashboardPage/Onboarding 覆盖时 BrowserShell 不可见 */
  private covering: boolean = false`;
if (CRLF) { a3 = a3.replace(/\n/g, '\r\n'); b3 = b3.replace(/\n/g, '\r\n'); }
must(s.split(a3).length - 1, 'patch3');
s = s.replace(a3, b3);

let a4 = `  onPageShow(): void {
    console.info('BrowserShell onPageShow: resync tab state')
    this.syncFromTabManager()
  }`;
let b4 = `  onPageShow(): void {
    console.info('BrowserShell onPageShow: resync tab state')
    this.covering = false
    this.syncFromTabManager()
  }

  onPageHide(): void {
    console.info('BrowserShell onPageHide: entering cover state')
    this.covering = true
  }`;
if (CRLF) { a4 = a4.replace(/\n/g, '\r\n'); b4 = b4.replace(/\n/g, '\r\n'); }
must(s.split(a4).length - 1, 'patch4');
s = s.replace(a4, b4);

fs.writeFileSync(path, s);
console.log('PATCHED part2 OK');
