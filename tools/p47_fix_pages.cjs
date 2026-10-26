/* P47 fix pages: rename border()->brd(), fix doImport promise compare */
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages';

function fixPage(path, extra) {
  let s = fs.readFileSync(path, 'utf8');
  const eol = s.includes('\r\n') ? '\r\n' : '\n';
  s = s.replace(/\r\n/g, '\n');
  // rename private border() helper (declaration + all call sites)
  s = s.replace(/private border\(\): string \{/, 'private brd(): string {');
  s = s.replace(/this\.border\(\)/g, 'this.brd()');
  if (extra) s = extra(s);
  fs.writeFileSync(path, eol === '\r\n' ? s.replace(/\n/g, '\r\n') : s, 'utf8');
  console.log('fixed', path);
}

// PasswordsPage: doImport sync version
fixPage(P + '/PasswordsPage.ets', (s) => {
  s = s.replace(
    "  private doImport(): void {\n    const r = CredentialStore.importBitwardenJson(this.importText)\n    if (r < 0) {",
    "  private doImport(): void {\n    const r: number = CredentialStore.importBitwardenJson(this.importText)\n    if (r < 0) {");
  // CredentialStore.add now sync void — saveEdit chain fix
  s = s.replace(
    "    if (this.editId.length === 0) {\n      CredentialStore.add(this.editDomain.trim(), this.editUsername.trim(), this.editPassword).then(() => {\n        this.editOpen = false\n        this.refresh()\n      })\n    } else {\n      CredentialStore.update(this.editId, this.editDomain.trim(), this.editUsername.trim(), this.editPassword).then(() => {\n        this.editOpen = false\n        this.refresh()\n      })\n    }",
    "    if (this.editId.length === 0) {\n      CredentialStore.add(this.editDomain.trim(), this.editUsername.trim(), this.editPassword)\n      this.editOpen = false\n      this.refresh()\n    } else {\n      CredentialStore.update(this.editId, this.editDomain.trim(), this.editUsername.trim(), this.editPassword)\n      this.editOpen = false\n      this.refresh()\n    }");
  s = s.replace(
    "  private removeCred(id: string): void {\n    CredentialStore.remove(id).then(() => {\n      this.refresh()\n    })\n  }",
    "  private removeCred(id: string): void {\n    CredentialStore.remove(id)\n    this.refresh()\n  }");
  s = s.replace(
    "  private clearAll(): void {\n    CredentialStore.clearAll().then(() => {\n      this.refresh()\n    })\n  }",
    "  private clearAll(): void {\n    CredentialStore.clearAll()\n    this.refresh()\n  }");
  return s;
});

// DevToolsPage: no extra (border rename covers)
fixPage(P + '/DevToolsPage.ets', null);
console.log('ALL FIXED');
