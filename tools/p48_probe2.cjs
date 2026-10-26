const fs = require('fs')
const rd = (f) => fs.readFileSync(f, 'utf8')
// BrowserShell: localeVersion build 锚
{
  const F = 'entry/src/main/ets/pages/BrowserShell.ets'
  let s = rd(F)
  if (!s.includes('localeVersion < 0')) {
    const anchor = "if (this.themeVersion < 0) {"
    const i = s.indexOf(anchor)
    if (i >= 0) {
      // 找到该 if 块结束 }，在其后插 locale 锚
      const blockEnd = s.indexOf('}', i) + 1
      const CRLF = s.includes('\r\n') ? '\r\n' : '\n'
      const ins = CRLF + '        // P48: localeVersion 渲染依赖锚（语言切换全树重渲染）' + CRLF +
        '        if (this.localeVersion < 0) {' + CRLF + "          Text('').fontSize(0)" + CRLF + '        }'
      s = s.substring(0, blockEnd) + ins + s.substring(blockEnd)
      fs.writeFileSync(F, s)
      console.log('BrowserShell: locale build anchor added')
    }
  } else console.log('BrowserShell: anchor exists')
}
// AgentSidePanel: starter/modelOptions 字段
{
  const s = rd('entry/src/main/ets/components/AgentSidePanel.ets')
  const m = s.match(/private readonly (\w+): StarterPrompt\[\] = \[/)
  console.log('ASP starter field:', m ? m[1] : 'none')
  const mo = s.match(/private readonly (modelOptions): string\[\] = \[/)
  console.log('ASP modelOptions:', mo ? 'FIELD' : 'none')
}
// NeoDashboardPanel CONNECTORS
{
  const s = rd('entry/src/main/ets/components/NeoDashboardPanel.ets')
  const m = s.match(/(private|const) (?:readonly )?(CONNECTORS)[^\n]*=[^\n]*\[/)
  console.log('NDP CONNECTORS:', m ? m[2] + ' at ' + (m[1] === 'const' ? 'module-level const' : 'field') : 'none')
}
// SkillsPage 默认技能数组
{
  const s = rd('entry/src/main/ets/pages/SkillsPage.ets')
  const m = s.match(/(private|const)[^\n=]*\w*[Dd]efault\w*[^\n=]*=[^\n]*\[/)
  console.log('SkillsPage defaults:', m ? m[0].substring(0, 80) : 'none')
}
// JtbdSurveyPage 问题数组
{
  const s = rd('entry/src/main/ets/pages/JtbdSurveyPage.ets')
  const m = s.match(/(private|const)[^\n=]*question[^\n=]*=[^\n]*\[/i)
  console.log('JtbdSurvey questions:', m ? m[0].substring(0, 80) : 'none')
}
// ChromeWidgets OmniboxSuggestions suggestions
{
  const s = rd('entry/src/main/ets/components/ChromeWidgets.ets')
  console.log('CW residual field-array I18n:', (s.match(/private readonly \w+[^=]*= \[[^\]]*I18n\.t/s) || ['none'])[0].substring(0, 60))
}
