#!/usr/bin/env node
/* P48 一致性校验：zh/en 字段一致 + 文件完整性抽查 */
const fs = require('fs')
const path = require('path')
const ROOT = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/common'

function keysOf(f) {
  const s = fs.readFileSync(path.join(ROOT, f), 'utf8')
  if (!s.includes('export function build')) throw new Error(f + ': missing export function')
  const out = []
  const re = /^\s+\['(\w+)', /gm
  let m
  while ((m = re.exec(s))) out.push(m[1])
  if (out.length === 0) throw new Error(f + ': 0 pairs (empty/contaminated)')
  return out
}

const zh = keysOf('I18nZh.ets')
const en = keysOf('I18nEn.ets')
const zhSet = new Set(zh)
const enSet = new Set(en)
let fail = false
if (zh.length !== en.length) { console.log('COUNT MISMATCH zh=' + zh.length + ' en=' + en.length); fail = true }
for (const k of zh) if (!enSet.has(k)) { console.log('MISSING in EN: ' + k); fail = true }
for (const k of en) if (!zhSet.has(k)) { console.log('MISSING in ZH: ' + k); fail = true }
const dup = (a) => a.filter((x, i) => a.indexOf(x) !== i)
if (dup(zh).length) { console.log('DUP ZH: ' + dup(zh).join(',')); fail = true }
if (dup(en).length) { console.log('DUP EN: ' + dup(en).join(',')); fail = true }

const i18n = fs.readFileSync(path.join(ROOT, 'I18n.ets'), 'utf8')
for (const probe of ["export const I18n = new I18nImpl()", "app_locale", "setLocale", "I18nZh", "I18nEn"]) {
  if (!i18n.includes(probe)) { console.log('I18n.ets missing: ' + probe); fail = true }
}
// 污染探测：非 ASCII 垃圾 token / 重复段落
if (/class_|\bappcatch\b|callI18n/.test(i18n)) { console.log('I18n.ets CONTAMINATED'); fail = true }
const zhS = fs.readFileSync(path.join(ROOT, 'I18nZh.ets'), 'utf8')
const enS = fs.readFileSync(path.join(ROOT, 'I18nEn.ets'), 'utf8')
if (/class_|\bappcatch\b/.test(zhS) || /class_|\bappcatch\b/.test(enS)) { console.log('PACK CONTAMINATED'); fail = true }

console.log(fail ? 'FAIL' : 'PASS zh=' + zh.length + ' en=' + en.length)
process.exit(fail ? 1 : 0)
