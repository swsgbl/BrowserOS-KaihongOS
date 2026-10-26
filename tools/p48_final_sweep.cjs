#!/usr/bin/env node
/* P48 最后一轮：补 SessionPlayer/ViewSource/JtbdSurvey/Skills默认描述 + 计数残留 */
const fs = require('fs')
const zhNew = [
  ['spRecording', '此为录制时截图，实际页面可能已变化'],
  ['spNoShot', '无截图数据'],
  ['spReplay', '回放'],
  ['spTimeline', '时间线'],
  ['spTabs', '标签页'],
  ['spPause', '暂停'],
  ['spPlay', '播放'],
  ['spSessionTabs', '会话标签页'],
  ['spNoTabData', '本会话未记录标签页数据'],
  ['spOpTimeline', '操作时间线'],
  ['vsFetchFail', '源码获取失败: '],
  ['vsLoadFail', '页面加载失败: '],
  ['vsLoading', '正在获取源码…'],
  ['jtQ1', '你主要用 BrowserOS 做什么？'],
  ['jtQ2', '你最想要什么改进？'],
  ['jtQ3', '你愿意把 BrowserOS 推荐给朋友吗？'],
  ['jtTitle', 'BrowserOS 调查'],
  ['jtInputPh', '输入你的回答…'],
  ['skDefDesc1', '总结当前页面为三句话要点'],
  ['skDefDesc2', '监控商品页价格并变动提醒'],
  ['skDefDesc3', '用预存资料自动填当前表单'],
]
const enNew = [
  ['spRecording', 'This is a screenshot taken during recording; the actual page may have changed'],
  ['spNoShot', 'No screenshot data'],
  ['spReplay', 'Replay'],
  ['spTimeline', 'Timeline'],
  ['spTabs', 'Tabs'],
  ['spPause', 'Pause'],
  ['spPlay', 'Play'],
  ['spSessionTabs', 'Session tabs'],
  ['spNoTabData', 'No tab data recorded for this session'],
  ['spOpTimeline', 'Operation timeline'],
  ['vsFetchFail', 'Failed to fetch source: '],
  ['vsLoadFail', 'Page load failed: '],
  ['vsLoading', 'Fetching source…'],
  ['jtQ1', 'What do you mainly use BrowserOS for?'],
  ['jtQ2', 'What improvement do you want most?'],
  ['jtQ3', 'Would you recommend BrowserOS to friends?'],
  ['jtTitle', 'BrowserOS survey'],
  ['jtInputPh', 'Type your answer…'],
  ['skDefDesc1', 'Summarize the current page in three bullet points'],
  ['skDefDesc2', 'Monitor product page prices and alert on changes'],
  ['skDefDesc3', 'Auto-fill the current form with saved profiles'],
]
function insert(file, rows) {
  let s = fs.readFileSync(file, 'utf8')
  const anchor = "  ['clLine4', "
  const i = s.indexOf(anchor)
  const lineEnd = s.indexOf('\n', i) + 1
  const block = rows.map(r => "  ['" + r[0] + "', '" + r[1].replace(/'/g, "\\'") + "'],").join('\n') + '\n'
  s = s.substring(0, lineEnd) + block + s.substring(lineEnd)
  fs.writeFileSync(file, s)
  console.log(file + ': +' + rows.length)
}
insert('entry/src/main/ets/common/I18nZh.ets', zhNew)
insert('entry/src/main/ets/common/I18nEn.ets', enNew)

// 逐文件替换
const jobs = [
  ['entry/src/main/ets/pages/BookmarksPage.ets', [
    ["Text(`${this.filtered().length} 条`)", "Text(`${this.filtered().length}` + I18n.t('ntCountEnd'))"],
  ]],
  ['entry/src/main/ets/pages/DownloadsPage.ets', [
    ["Text(this.items.length + ' 项')", "Text(this.items.length + I18n.t('dlItem'))"],
  ]],
  ['entry/src/main/ets/pages/HistoryPage.ets', [
    [".accessibilityText('返回')", ".accessibilityText(I18n.t('back'))"],
    ["Text(`${this.entries.length} 条`)", "Text(`${this.entries.length}` + I18n.t('ntCountEnd'))"],
  ]],
  ['entry/src/main/ets/pages/LlmHubPage.ets', [
    [".accessibilityText('返回')", ".accessibilityText(I18n.t('back'))"],
  ]],
  ['entry/src/main/ets/pages/ScheduledTasksPage.ets', [
    [".accessibilityText('返回')", ".accessibilityText(I18n.t('back'))"],
  ]],
  ['entry/src/main/ets/pages/SessionPlayerPage.ets', [
    ["Text('此为录制时截图，实际页面可能已变化')", "Text(I18n.t('spRecording'))"],
    ["Button('关闭')", "Button(I18n.t('close'))"],
    ["Text('无截图数据')", "Text(I18n.t('spNoShot'))"],
    ["this.TabItem('回放', 0)", "this.TabItem(I18n.t('spReplay'), 0)"],
    ["this.TabItem('时间线', 1)", "this.TabItem(I18n.t('spTimeline'), 1)"],
    ["this.TabItem('标签页', 2)", "this.TabItem(I18n.t('spTabs'), 2)"],
    ["Button(this.isPlaying ? '暂停' : '播放')", "Button(this.isPlaying ? I18n.t('spPause') : I18n.t('spPlay'))"],
    ["Button('停止')", "Button(I18n.t('asStop'))"],
    ["Text('会话标签页')", "Text(I18n.t('spSessionTabs'))"],
    ["Text('本会话未记录标签页数据')", "Text(I18n.t('spNoTabData'))"],
    ["Text('操作时间线')", "Text(I18n.t('spOpTimeline'))"],
  ]],
  ['entry/src/main/ets/pages/ViewSourcePage.ets', [
    ["this.failed = '源码获取失败: ' + err", "this.failed = I18n.t('vsFetchFail') + err"],
    ["this.failed = '页面加载失败: ' + (event.error ? event.error.getErrorInfo() : 'unknown')", "this.failed = I18n.t('vsLoadFail') + (event.error ? event.error.getErrorInfo() : 'unknown')"],
    ["Text('关闭')", "Text(I18n.t('close'))"],
    ["Text('正在获取源码…')", "Text(I18n.t('vsLoading'))"],
  ]],
  ['entry/src/main/ets/pages/JtbdSurveyPage.ets', [
    ["'你主要用 BrowserOS 做什么？',", "I18n.t('jtQ1'),"],
    ["'你最想要什么改进？',", "I18n.t('jtQ2'),"],
    ["'你愿意把 BrowserOS 推荐给朋友吗？'", "I18n.t('jtQ3')"],
    ["Text('BrowserOS 调查')", "Text(I18n.t('jtTitle'))"],
    ["Button('返回浏览器')", "Button(I18n.t('stBackBrowser'))"],
    ["TextInput({ text: this.inputText, placeholder: '输入你的回答…' })", "TextInput({ text: this.inputText, placeholder: I18n.t('jtInputPh') })"],
    ["Button('发送')", "Button(I18n.t('tbSend'))"],
  ]],
  ['entry/src/main/ets/pages/SkillsPage.ets', [
    ["description: '总结当前页面为三句话要点',", "description: I18n.t('skDefDesc1'),"],
    ["description: '监控商品页价格并变动提醒',", "description: I18n.t('skDefDesc2'),"],
    ["description: '用预存资料自动填当前表单',", "description: I18n.t('skDefDesc3'),"],
  ]],
]
for (const [f, rules] of jobs) {
  let s = fs.readFileSync(f, 'utf8')
  const CRLF = s.includes('\r\n') ? '\r\n' : '\n'
  let ok = 0, miss = 0
  for (const [from, to] of rules) {
    const n = s.split(from).length - 1
    if (n === 0) { console.log('  MISS ' + f.split('/').pop() + ': ' + from.substring(0, 50)); miss++; continue }
    s = s.split(from).join(to)
    ok += n
  }
  if (!s.includes("common/I18n")) {
    const m = s.match(/^import[^\n]*\n/m)
    if (m) { s = s.replace(m[0], m[0] + "import { I18n } from '../common/I18n'" + CRLF); console.log(f.split('/').pop() + ': import added') }
  }
  if (!s.includes("app_locale")) {
    const m = s.match(/@Component\s*(?:export\s+)?struct \w+ \{/)
    if (m) {
      const i = s.indexOf(m[0]) + m[0].length
      const inject = CRLF + "  // P48: locale 刷新锚" + CRLF + "  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'" + CRLF + "  @State localeVersion: number = 0" + CRLF + CRLF + "  onLocaleFlip(): void {" + CRLF + "    this.localeVersion++" + CRLF + "  }"
      s = s.substring(0, i) + inject + s.substring(i)
    }
  }
  fs.writeFileSync(f, s)
  console.log(f.split('/').pop() + ': applied=' + ok + ' miss=' + miss)
}
