/* P47 fix BrowserShell: CredentialStore API now sync (module singleton) */
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/BrowserShell.ets';
let s = fs.readFileSync(P, 'utf8');
const eol = s.includes('\r\n') ? '\r\n' : '\n';
s = s.replace(/\r\n/g, '\n');
const patches = [
  // init: no await needed (sync getSync inside)
  ["    if (p47ctx) {\n      CredentialStore.init(p47ctx)\n    }",
   "    if (p47ctx) {\n      CredentialStore.init(p47ctx)\n    }"],
  // p47DoSave: .then chain -> sync
  ["    CredentialStore.add(this.p47SaveDomain, user, this.p47SavePass).then(() => {\n      console.info('[P47] credential saved: ' + this.p47SaveDomain)\n      this.p47SaveOpen = false\n    })",
   "    CredentialStore.add(this.p47SaveDomain, user, this.p47SavePass)\n    console.info('[P47] credential saved: ' + this.p47SaveDomain)\n    this.p47SaveOpen = false"],
];
for (const [o, n] of patches) {
  const i = s.indexOf(o);
  if (i < 0) { console.log('MISS:', o.slice(0, 60)); process.exit(1); }
  s = s.slice(0, i) + n + s.slice(i + o.length);
}
fs.writeFileSync(P, eol === '\r\n' ? s.replace(/\n/g, '\r\n') : s, 'utf8');
console.log('BrowserShell sync-API fixed');
