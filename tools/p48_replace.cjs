#!/usr/bin/env node
/**
 * P48 批量替换引擎：把 .ets 文件里的硬编码中文 UI 字符串替换为 I18n.t('key')
 * 规则驱动（per-file rules），每条规则 = [匹配串, 替换模板]，匹配串在文件内唯一时才替换。
 * 用法: node p48_replace.cjs <rules.json> <file...>
 */
const fs = require('fs')

const rulesFile = process.argv[2]
const files = process.argv.slice(3)
const rules = JSON.parse(fs.readFileSync(rulesFile, 'utf8'))

for (const f of files) {
  let s = fs.readFileSync(f, 'utf8')
  let applied = 0
  const misses = []
  for (const [from, to] of rules) {
    const n = s.split(from).length - 1
    if (n === 0) { misses.push(from); continue }
    if (n > 1) { console.log(`SKIP(multi ${n}): ${f} :: ${from}`); continue }
    s = s.replace(from, to)
    applied++
  }
  fs.writeFileSync(f, s)
  console.log(`${f}: applied=${applied} miss=${misses.length}`)
  if (misses.length) misses.forEach(m => console.log(`  MISS: ${JSON.stringify(m).substring(0, 120)}`))
}
