#!/usr/bin/env node
/* P48 追加 OnboardingPage 漏的 24 条 key 到 zh/en 语言包（插在 clLine4 后） */
const fs = require('fs')
const zhNew = [
  ['obConnectTools', '连接AI工具'],
  ['obConnectDesc', 'BrowserOS会自动检测本地已安装的AI工具，一键连接即可使用。'],
  ['obNoTools', '未检测到已安装的AI工具'],
  ['obInstallFirst', '请先安装 Claude Code、Codex 或 Cursor'],
  ['obConnected', '已连接'],
  ['obConnectBtn', '连接'],
  ['obImportLoginTitle', '导入登录状态'],
  ['obImportDesc', '一键导入Chrome的登录状态，让AI代理使用你的真实账户。'],
  ['obImporting', '正在导入...'],
  ['obImportedN', '已导入 '],
  ['obImportedEnd', ' 个网站的登录状态'],
  ['obImportChromeBtn', '导入Chrome登录状态'],
  ['obDemo', '功能演示'],
  ['obDemoDesc', '以下是BrowserOS KaihongOS的核心功能演示：'],
  ['obDemo1', '1. AI代理浏览网页'],
  ['obDemo1d', '   代理在独立标签页中自动浏览网页，执行点击、输入等操作'],
  ['obDemo2', '2. 实时仪表盘'],
  ['obDemo2d', '   新标签页展示所有代理的实时工作状态'],
  ['obDemo3', '3. 会话回放'],
  ['obDemo3d', '   每个会话自动录制，可随时回放查看代理操作过程'],
  ['obDemo4', '4. MCP协议'],
  ['obDemo4d', '   10个标准工具：navigate/click/type/screenshot/snapshot等'],
  ['obSetupDone', '设置完成!'],
  ['obReady', 'BrowserOS KaihongOS 已准备就绪'],
  ['obReadyDesc', '现在你可以开始使用AI代理浏览网页了'],
]
const enNew = [
  ['obConnectTools', 'Connect AI tools'],
  ['obConnectDesc', 'BrowserOS automatically detects locally installed AI tools. One click to connect.'],
  ['obNoTools', 'No installed AI tools detected'],
  ['obInstallFirst', 'Install Claude Code, Codex or Cursor first'],
  ['obConnected', 'Connected'],
  ['obConnectBtn', 'Connect'],
  ['obImportLoginTitle', 'Import login state'],
  ['obImportDesc', 'Import your Chrome login state in one click so agents use your real accounts.'],
  ['obImporting', 'Importing...'],
  ['obImportedN', 'Imported login state for '],
  ['obImportedEnd', ' sites'],
  ['obImportChromeBtn', 'Import Chrome login state'],
  ['obDemo', 'Feature demo'],
  ['obDemoDesc', 'Core features of BrowserOS KaihongOS:'],
  ['obDemo1', '1. AI agents browse the web'],
  ['obDemo1d', '   Agents browse automatically in dedicated tabs, clicking and typing'],
  ['obDemo2', '2. Real-time dashboard'],
  ['obDemo2d', '   The new tab page shows live status of all agents'],
  ['obDemo3', '3. Session replay'],
  ['obDemo3d', '   Every session is recorded and can be replayed at any time'],
  ['obDemo4', '4. MCP protocol'],
  ['obDemo4d', '   10 standard tools: navigate/click/type/screenshot/snapshot etc.'],
  ['obSetupDone', 'Setup complete!'],
  ['obReady', 'BrowserOS KaihongOS is ready'],
  ['obReadyDesc', 'You can now start browsing with AI agents'],
]
function insert(file, rows) {
  let s = fs.readFileSync(file, 'utf8')
  const anchor = "  ['clLine4', "
  const i = s.indexOf(anchor)
  if (i < 0) throw new Error('anchor missing in ' + file)
  const lineStart = s.lastIndexOf('\n', i) + 1
  const lineEnd = s.indexOf('\n', i) + 1
  const block = rows.map(r => "  ['" + r[0] + "', " + JSON.stringify(r[1]).replace(/^"|"$/g, "'") + "],").join('\n') + '\n'
  s = s.substring(0, lineEnd) + block + s.substring(lineEnd)
  fs.writeFileSync(file, s)
  console.log(file + ': +' + rows.length)
}
insert('entry/src/main/ets/common/I18nZh.ets', zhNew)
insert('entry/src/main/ets/common/I18nEn.ets', enNew)
