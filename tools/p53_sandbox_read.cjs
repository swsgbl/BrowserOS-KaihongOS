const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/LoginStateManager.ets'
let t = fs.readFileSync(P, 'utf8')
const anchor = "  /** P53: \u4ece\u6587\u4ef6 URI \u8bfb\u53d6\u6587\u672c\uff08DocumentViewPicker \u8fd4\u56de\u7684 uri \u76f4\u63a5\u53ef open\uff09 */"
if (!t.includes(anchor)) { console.error('MISS anchor'); process.exit(1) }
const add = [
  '  /** P53: \u6c99\u76d2 filesDir \u76f8\u5bf9\u8def\u5f84\u76f4\u8bfb\uff08adb \u9884\u7f6e\u6587\u4ef6\u540e\u7684\u53ef\u9760\u5bfc\u5165\u901a\u9053\uff09 */',
  '  readSandboxText(relPath: string): string {',
  '    try {',
  '      const ctx = this.context',
  '      if (!ctx) {',
  "        console.error('LoginStateManager readSandboxText: no context')",
  '        return \'\'',
  '      }',
  "      const cleaned = relPath.replace(/^files\\//, '')",
  "      const full = ctx.filesDir + '/' + cleaned",
  '      return this.readTextFromUri(full)',
  '    } catch (e) {',
  "      console.error('LoginStateManager readSandboxText failed: ' + e)",
  '      return \'\'',
  '    }',
  '  }',
  ''
].join('\r\n')
t = t.replace(anchor, add + '\r\n' + anchor)
fs.writeFileSync(P, t, 'utf8')
console.log('OK readSandboxText added')
