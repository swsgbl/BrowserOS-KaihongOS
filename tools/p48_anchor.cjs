#!/usr/bin/env node
/* P48: 批量 import + struct 刷新锚注入（通用版：处理已替换完的 pages/components） */
const fs = require('fs')
const files = process.argv.slice(2)
const importPath = (f) => f.includes('/pages/') ? '../common/I18n' : '../common/I18n'
for (const f of files) {
  let s = fs.readFileSync(f, 'utf8')
  const CRLF = s.includes('\r\n') ? '\r\n' : '\n'
  let changed = []
  if (!s.includes("common/I18n")) {
    const m = s.match(/^import[^\n]*\n/m)
    if (m) {
      s = s.replace(m[0], m[0] + "import { I18n } from '" + importPath(f) + "'" + CRLF)
      changed.push('import')
    }
  }
  if (!s.includes("app_locale")) {
    // 找第一个 @Component struct 声明，在其后插入锚
    const m = s.match(/@Component\w*\s*(?:export\s+)?struct \w+ \{/)
    if (m) {
      const i = s.indexOf(m[0]) + m[0].length
      const inject = CRLF + "  // P48: locale 刷新锚" + CRLF + "  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'" + CRLF + "  @State localeVersion: number = 0" + CRLF + CRLF + "  onLocaleFlip(): void {" + CRLF + "    this.localeVersion++" + CRLF + "  }"
      s = s.substring(0, i) + inject + s.substring(i)
      changed.push('anchor')
    }
  }
  fs.writeFileSync(f, s)
  console.log(f.split('/').pop() + ': ' + (changed.join('+') || 'noop'))
}
