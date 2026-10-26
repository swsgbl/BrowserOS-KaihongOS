#!/usr/bin/env node
/* P48 修复轮2：剩余一次性求值数组 → getter/函数 */
const fs = require('fs')
// 1. AgentSidePanel modelOptions
{
  const F = 'entry/src/main/ets/components/AgentSidePanel.ets'
  let s = fs.readFileSync(F, 'utf8')
  const m = s.match(/private readonly modelOptions: string\[\] = (\[[\s\S]*?\])\n/)
  if (m) {
    s = s.replace(m[0], `private get modelOptions(): string[] {\n    return ${m[1].replace(/\n/g, '\n  ')}\n  }\n`)
    fs.writeFileSync(F, s)
    console.log('ASP modelOptions -> getter')
  } else console.log('ASP modelOptions NOT FOUND')
}
// 2. JtbdSurveyPage QUESTIONS
{
  const F = 'entry/src/main/ets/pages/JtbdSurveyPage.ets'
  let s = fs.readFileSync(F, 'utf8')
  const m = s.match(/private readonly QUESTIONS: string\[\] = (\[[\s\S]*?\n  \])\n/)
  if (m) {
    s = s.replace(m[0], `private get QUESTIONS(): string[] {\n    return ${m[1].replace(/\n/g, '\n  ')}\n  }\n`)
    fs.writeFileSync(F, s)
    console.log('Jtbd QUESTIONS -> getter')
  } else console.log('Jtbd QUESTIONS NOT FOUND')
}
// 3. NeoDashboardPanel CONNECTORS（模块级 const → 函数）
{
  const F = 'entry/src/main/ets/components/NeoDashboardPanel.ets'
  let s = fs.readFileSync(F, 'utf8')
  const m = s.match(/const CONNECTORS[^=]*= (\[[\s\S]*?\n\])\n/)
  if (m) {
    s = s.replace(m[0], `function CONNECTORS_LIST(): ConnectorDesc[] {\n  return ${m[1].replace(/\n/g, '\n  ')}\n}\n`)
    // 引用替换
    s = s.split('CONNECTORS.length').join('CONNECTORS_LIST().length')
    s = s.split('ForEach(CONNECTORS,').join('ForEach(CONNECTORS_LIST(),')
    s = s.split('for (const c of CONNECTORS)').join('for (const c of CONNECTORS_LIST())')
    fs.writeFileSync(F, s)
    console.log('NDP CONNECTORS -> function (refs updated)')
  } else console.log('NDP CONNECTORS NOT FOUND')
}
