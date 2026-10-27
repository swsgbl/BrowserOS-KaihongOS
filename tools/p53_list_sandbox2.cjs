const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/service/LoginStateManager.ets'
let t = fs.readFileSync(P, 'utf8')
const anchor = '  readSandboxText(relPath: string): string {'
if (!t.includes(anchor)) { console.error('MISS'); process.exit(1) }
const add = [
  '  /** P53: 扫描沙盒 filesDir 下可导入文件（.txt/.json，忽略隐藏项） */',
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
// 插在 readSandboxText 前一行（它的注释行是 CRLF 且前面有空行）
const idx = t.indexOf(anchor)
const lineStart = t.lastIndexOf('\n', idx - 1) + 1
t = t.slice(0, lineStart) + add + '\r\n' + t.slice(lineStart)
fs.writeFileSync(P, t, 'utf8')
console.log('OK listSandboxImportable added')
