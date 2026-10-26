/**
 * P47-A: DevTools 页面 —— Console / Network / Info 三标签
 * 数据来自 DevToolsCollector（BrowserShell onConsole/onInterceptRequest 写入）
 * JS 求值通过 TabManager 活动标签的 controller runJavaScript 执行
 */
import { DevToolsCollector, ConsoleLogEntry, NetworkEntry, DtLogLevel } from '../service/DevToolsCollector'
import { I18n } from '../common/I18n'
import { TabManager } from '../service/TabManager'
import { router } from '@kit.ArkUI'

@Entry
@Component
struct DevToolsPage {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false
  @State themeVersion: number = 0
  @State tabIdx: number = 0 // 0=Console 1=Network 2=Info
  @State consoleLogs: ConsoleLogEntry[] = []
  @State networkLogs: NetworkEntry[] = []
  @State evalInput: string = ''
  @State evalHistory: string[] = []
  @State expandedNet: number = -1
  // Info
  @State infoUrl: string = ''
  @State infoTitle: string = ''
  @State infoUa: string = ''
  @State infoLoadMs: string = ''
  private timerId: number = -1

  private bg(): string {
    return '#202124'
  }
  private panel(): string {
    return '#292A2D'
  }
  private row1(): string {
    return '#1B1B1D'
  }
  private text(): string {
    return '#E8EAED'
  }
  private text2(): string {
    return '#9AA0A6'
  }
  private brd(): string {
    return '#3C4043'
  }

  onThemeFlip(): void {
    this.themeVersion++
  }

  aboutToAppear(): void {
    this.refreshData()
    this.loadInfo()
    // 轮询刷新（日志实时追加）
    this.timerId = setInterval(() => {
      this.refreshData()
    }, 1000)
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private activeTabId(): string {
    return TabManager.getActiveTabId()
  }

  private refreshData(): void {
    const id = this.activeTabId()
    this.consoleLogs = DevToolsCollector.getConsole(id).slice()
    this.networkLogs = DevToolsCollector.getNetwork(id).slice()
  }

  private loadInfo(): void {
    const id = this.activeTabId()
    const tab = TabManager.getTab(id)
    this.infoUrl = tab && tab.currentUrl ? tab.currentUrl : I18n.t('dtNone')
    this.infoTitle = tab && tab.title ? tab.title : I18n.t('dtNone')
    const ctrl = TabManager.getWebView(id)
    if (ctrl) {
      ctrl.controller.runJavaScript('navigator.userAgent').then((r: string) => {
        this.infoUa = r.replace(/^"|"$/g, '')
      }).catch(() => {
        this.infoUa = I18n.t('dtNa')
      })
    }
    const logs = DevToolsCollector.getConsole(id)
    if (logs.length > 0) {
      this.infoLoadMs = I18n.t('dtConsoleN') + logs.length
    } else {
      this.infoLoadMs = I18n.t('dtConsole0')
    }
  }

  private levelColor(l: DtLogLevel): string {
    if (l === DtLogLevel.ERROR) {
      return '#F28B82'
    }
    if (l === DtLogLevel.WARN) {
      return '#FDD663'
    }
    if (l === DtLogLevel.DEBUG) {
      return '#9AA0A6'
    }
    return '#E8EAED'
  }

  private levelName(l: DtLogLevel): string {
    if (l === DtLogLevel.ERROR) {
      return 'error'
    }
    if (l === DtLogLevel.WARN) {
      return 'warn'
    }
    if (l === DtLogLevel.DEBUG) {
      return 'debug'
    }
    return 'info'
  }

  private tsLabel(ts: number): string {
    const d = new Date(ts)
    const pad = (n: number): string => (n < 10 ? '0' + n : '' + n)
    return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
  }

  private runEval(): void {
    const code = this.evalInput.trim()
    if (code.length === 0) {
      return
    }
    const id = this.activeTabId()
    const wv = TabManager.getWebView(id)
    if (!wv) {
      this.evalHistory.unshift('> ' + code)
      this.evalHistory.unshift(I18n.t('dtErrNoWebview'))
      return
    }
    this.evalHistory.unshift('> ' + code)
    wv.controller.runJavaScript(code).then((r: string) => {
      this.evalHistory.unshift('< ' + r)
      console.info('[P47] devtools eval ok')
    }).catch((e: Object) => {
      this.evalHistory.unshift(I18n.t('dtErrPre') + e)
    })
    this.evalInput = ''
  }

  private clearLogs(): void {
    const id = this.activeTabId()
    if (this.tabIdx === 0) {
      DevToolsCollector.clearConsole(id)
    } else {
      DevToolsCollector.clearNetwork(id)
    }
    this.refreshData()
  }

  build(): void {
    Stack() {
      Column() {
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }
        // 顶栏
        Row() {
          Button({ type: ButtonType.Normal }) {
            Image($rawfile('ic_back.svg'))
              .width(20).height(20)
              .fillColor(this.text2())
              .draggable(false)
          }
          .width(36).height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back() })
          Text(I18n.t('dtTitle'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.text())
            .layoutWeight(1)
          Text('tab: ' + this.activeTabId().substring(0, 10))
            .fontSize(10)
            .fontColor(this.text2())
            .margin({ right: 8 })
          Button(I18n.t('dtClear'))
            .fontSize(12)
            .height(30)
            .backgroundColor(this.panel())
            .fontColor(this.text())
            .onClick(() => { this.clearLogs() })
        }
        .width('100%')
        .height(48)
        .padding({ left: 8, right: 8 })
        .backgroundColor(this.panel())

        // Tab 条
        Row() {
          ForEach(['Console', 'Network', 'Info'], (name: string, idx: number) => {
            Text(name)
              .fontSize(13)
              .fontWeight(this.tabIdx === idx ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.tabIdx === idx ? '#8AB4F8' : this.text2())
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .border({ width: { bottom: 2 }, color: this.tabIdx === idx ? '#8AB4F8' : Color.Transparent.toString() })
              .onClick(() => {
                this.tabIdx = idx
                if (idx === 2) {
                  this.loadInfo()
                }
              })
          }, (name: string) => name)
        }
        .width('100%')
        .backgroundColor(this.panel())

        // 内容区
        Column() {
          if (this.tabIdx === 0) {
            this.ConsoleTab()
          } else if (this.tabIdx === 1) {
            this.NetworkTab()
          } else {
            this.InfoTab()
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bg())
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ConsoleTab(): void {
    Column() {
      Scroll() {
        Column() {
          if (this.consoleLogs.length === 0 && this.evalHistory.length === 0) {
            Text(I18n.t('dtNoConsole'))
              .fontSize(12)
              .fontColor(this.text2())
              .textAlign(TextAlign.Center)
              .margin({ top: 80 })
          }
          // 求值历史（最新在上）
          ForEach(this.evalHistory, (line: string, idx: number) => {
            Text(line)
              .fontSize(12)
              .fontColor(line.startsWith('<') ? '#81C995' : '#8AB4F8')
              .fontFamily('monospace')
              .width('100%')
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor(idx % 2 === 0 ? this.row1() : Color.Transparent)
          }, (line: string, idx: number) => 'ev_' + idx + '_' + line.substring(0, 20))

          ForEach(this.consoleLogs, (log: ConsoleLogEntry, idx: number) => {
            Row() {
              Text(this.tsLabel(log.ts))
                .fontSize(10)
                .fontColor(this.text2())
                .fontFamily('monospace')
              Text(this.levelName(log.level))
                .fontSize(10)
                .fontColor(this.levelColor(log.level))
                .fontFamily('monospace')
                .margin({ left: 8 })
              Text(log.message)
                .fontSize(12)
                .fontColor(this.levelColor(log.level))
                .fontFamily('monospace')
                .layoutWeight(1)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(idx % 2 === 0 ? this.row1() : Color.Transparent)
            .alignItems(VerticalAlign.Top)
          }, (log: ConsoleLogEntry, idx: number) => 'cl_' + log.ts + '_' + idx)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)

      // 求值输入框
      Row() {
        Text('>')
          .fontSize(14)
          .fontColor('#8AB4F8')
          .fontFamily('monospace')
          .margin({ left: 10 })
        TextInput({ text: this.evalInput, placeholder: I18n.t('dtEvalPh') })
          .fontSize(12)
          .fontColor(this.text())
          .placeholderColor(this.text2())
          .fontFamily('monospace')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onChange((v: string) => { this.evalInput = v })
          .onSubmit(() => { this.runEval() })
      }
      .width('100%')
      .height(44)
      .backgroundColor(this.row1())
      .border({ width: { top: 1 }, color: this.brd() })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  NetworkTab(): void {
    Scroll() {
      Column() {
        if (this.networkLogs.length === 0) {
          Text(I18n.t('dtNoNet'))
            .fontSize(12)
            .fontColor(this.text2())
            .textAlign(TextAlign.Center)
            .margin({ top: 80 })
        }
        ForEach(this.networkLogs, (net: NetworkEntry, idx: number) => {
          Column() {
            Row() {
              Text(net.method)
                .fontSize(10)
                .fontColor('#8AB4F8')
                .fontFamily('monospace')
              Text(net.url)
                .fontSize(11)
                .fontColor(this.text())
                .fontFamily('monospace')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ left: 8 })
              Text(net.durationMs + 'ms')
                .fontSize(10)
                .fontColor(this.text2())
                .fontFamily('monospace')
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => {
              this.expandedNet = this.expandedNet === idx ? -1 : idx
            })

            if (this.expandedNet === idx) {
              Text('Headers: ' + (net.headers.length > 0 ? net.headers : I18n.t('dtNone')))
                .fontSize(10)
                .fontColor(this.text2())
                .fontFamily('monospace')
                .width('100%')
                .padding({ left: 24, right: 10, top: 2, bottom: 8 })
                .maxLines(8)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .backgroundColor(idx % 2 === 0 ? this.row1() : Color.Transparent)
        }, (net: NetworkEntry, idx: number) => 'net_' + net.ts + '_' + idx)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  InfoTab(): void {
    Scroll() {
      Column() {
        this.InfoRow('URL', this.infoUrl)
        this.InfoRow(I18n.t('dtTitleRow'), this.infoTitle)
        this.InfoRow('UserAgent', this.infoUa)
        this.InfoRow(I18n.t('dtStats'), this.infoLoadMs)
        this.InfoRow(I18n.t('dtNetCount'), '' + this.networkLogs.length)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  @Builder
  InfoRow(label: string, value: string): void {
    Column() {
      Text(label)
        .fontSize(11)
        .fontColor(this.text2())
      Text(value)
        .fontSize(12)
        .fontColor(this.text())
        .fontFamily('monospace')
        .margin({ top: 3 })
        .width('100%')
    }
    .width('94%')
    .padding(10)
    .borderRadius(8)
    .backgroundColor(this.row1())
    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
  }
}
