// LoginStateManager.listSandboxImportable
const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/LoginStateManager.ets'
let t = fs.readFileSync(P, 'utf8')
const anchor = "  /** P53: \u6c99\u76d8 filesDir \u76f8\u5bf9\u8def\u5f84\u76f4\u8bfb\uff08adb \u9884\u7f6e\u6587\u4ef6\u540e\u7684\u53ef\u9760\u5bfc\u5165\u901a\u9053\uff09 */"
if (!t.includes(anchor)) { console.error('MISS'); process.exit(1) }
const add = [
  '  /** P53: \u626b\u63cf\u6c99\u76d8 filesDir \u4e0b\u53ef\u5bfc\u5165\u6587\u4ef6\uff08.txt/.json\uff0c\u5ffd\u7565\u9690\u85cf\u9879\uff09 */',
  '  listSandboxImportable(): string[] {',
  '    const out: string[] = []',
  '    try {',
  '      const ctx = this.context',
  '      if (!ctx) {',
  '        return out',
  '      }',
  '      const names = fs.listFileSync(ctx.filesDir)',
  '      for (const n of names) {',
  "        if (n.startsWith('.')) {",
  '          continue',
  '        }',
  "        if (n.endsWith('.txt') || n.endsWith('.json')) {",
  '          out.push(n)',
  '        }',
  '      }',
  '    } catch (e) {',
  "      console.error('[P53] listSandboxImportable failed: ' + e)",
  '    }',
  '    return out',
  '  }',
  ''
].join('\r\n')
t = t.replace(anchor, add + '\r\n' + anchor)
fs.writeFileSync(P, t, 'utf8')
console.log('OK listSandboxImportable added')
