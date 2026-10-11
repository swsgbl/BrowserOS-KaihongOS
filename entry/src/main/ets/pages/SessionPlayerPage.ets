import { SessionManager, SessionReplayer } from '../service/SessionManager'
import { SessionRecord, ScreenshotEntry, OperationLog } from '../model/SessionRecord'
import { Constants } from '../common/Constants'
import { router } from '@kit.ArkUI'

/** P15: 操作步骤节点标记（进度条上按时间比例定位） */
interface TimelineMark {
  key: string
  time: number
  pct: number
}

@Entry
@Component
struct SessionPlayerPage {
  @State sessionId: string = ''
  @State session: SessionRecord | null = null
  @State isPlaying: boolean = false
  @State currentTime: number = 0
  @State speed: number = 1
  @State currentScreenshot: string = ''
  @State operationLogs: OperationLog[] = []
  @State showNotice: boolean = true
  @State marks: TimelineMark[] = []
  /** P25b: 顶部页签 0=回放 1=时间线 2=标签页 */
  @State activeTab: number = 0
  /** P25b: 会话标签页(URL 去重列表,数据源 session.urlSequence) */
  @State tabUrls: string[] = []
  private replayer: SessionReplayer | null = null

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, Object>
    if (p && p['sessionId'] !== undefined) {
      const v = p['sessionId'] as string
      if (v && v.length > 0) {
        this.sessionId = v
      }
    }
    if (this.sessionId) {
      this.loadSession()
    }
  }

  private async loadSession(): Promise<void> {
    const session = await SessionManager.getSessionDetail(this.sessionId)
    if (session) {
      this.session = session
      console.info('[SessionPlayer] loaded session=' + this.sessionId
        + ' shots=' + (session ? session.screenshots.length : 0)
        + ' logs=' + (session ? session.operationLogs.length : 0))
      this.replayer = await SessionManager.createReplayerAsync(this.sessionId)
      if (this.replayer) {
        this.currentTime = this.replayer.getCurrentTime()
        this.updateCurrentView()
      }
      this.rebuildMarks()
      this.rebuildTabUrls()
    }
  }

  /** P25b: 由 urlSequence 构建去重标签 URL 列表 */
  private rebuildTabUrls(): void {
    const out: string[] = []
    const seen: Set<string> = new Set<string>()
    const s = this.session
    if (s) {
      for (let i = 0; i < s.urlSequence.length; i++) {
        const u = s.urlSequence[i]
        if (u.length > 0 && !seen.has(u)) {
          seen.add(u)
          out.push(u)
        }
      }
    }
    this.tabUrls = out
    console.info('[SessionPlayer] tabUrls built: ' + out.length)
  }

  private updateCurrentView(): void {
    if (!this.replayer) {
      return
    }
    const screenshot = this.replayer.getCurrentScreenshot()
    if (screenshot) {
      this.currentScreenshot = screenshot.base64Data
    }
    this.operationLogs = this.replayer.getCurrentOperations()
  }

  /** P15: 由操作日志构建进度条节点标记（clamp 97% 防右溢出） */
  private rebuildMarks(): void {
    const out: TimelineMark[] = []
    const s = this.session
    if (!s || s.duration <= 0 || s.operationLogs.length === 0) {
      this.marks = out
      return
    }
    for (let i = 0; i < s.operationLogs.length; i++) {
      const log = s.operationLogs[i]
      const rel = log.timestamp - s.startTime
      let pct = Math.round(rel / s.duration * 100)
      if (pct < 0) {
        pct = 0
      }
      if (pct > 97) {
        pct = 97
      }
      out.push({ key: `mk_${i}_${log.timestamp}`, time: rel, pct: pct })
    }
    this.marks = out
    console.info('[SessionPlayer] marks built: ' + out.length)
  }

  /** P15: 操作类型 → 图标资源映射（navigate/click/type/scroll/snapshot/wait，其余用 check） */
  private opIcon(type: string): Resource {
    if (type === 'navigate' || type === 'back' || type === 'forward') {
      return $r('app.media.ic_op_navigate')
    }
    if (type === 'click') {
      return $r('app.media.ic_op_click')
    }
    if (type === 'type') {
      return $r('app.media.ic_op_type')
    }
    if (type === 'scroll') {
      return $r('app.media.ic_op_scroll')
    }
    if (type === 'snapshot') {
      return $r('app.media.ic_op_snapshot')
    }
    if (type === 'wait' || type === 'wait_for') {
      return $r('app.media.ic_op_wait')
    }
    return $r('app.media.ic_check')
  }

  build(): void {
    Column() {
      if (this.showNotice) {
        Row() {
          Text('此为录制时截图，实际页面可能已变化')
            .fontSize(12)
            .fontColor('#FF9800')
          Button('关闭')
            .fontSize(10)
            .height(20)
            .onClick(() => {
              this.showNotice = false
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        .backgroundColor('#FFF3E0')
      }

      // P25b: 顶部 Tab 条(Chrome 系下划线激活态)
      this.TabBar()

      if (this.activeTab === 0) {
        // 回放页签:截图 + 播放控件(原有布局)
        if (this.currentScreenshot) {
          Image(this.currentScreenshot)
            .width('100%')
            .layoutWeight(1)
            .objectFit(ImageFit.Contain)
        } else {
          Column() {
            Text('无截图数据')
              .fontSize(16)
              .fontColor('#999999')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        this.PlaybackControls()
      } else if (this.activeTab === 1) {
        // 时间线页签:List 自滚动,layoutWeight 直挂根 Column 高度链(防塌缩)
        this.OperationTimeline()
      } else {
        // 标签页页签:该会话涉及的 URL 去重列表
        Scroll() {
          Column() {
            this.TabsView()
          }
          .width('100%')
          .padding({ top: 4, bottom: 12 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  /** P25b: 顶部 Tab 条 —— 下划线激活态(Chrome 系) */
  @Builder
  TabBar(): void {
    Row() {
      this.TabItem('回放', 0)
      this.TabItem('时间线', 1)
      this.TabItem('标签页', 2)
    }
    .width('100%')
    .padding({ left: 16 })
    .constraintSize({ minHeight: 38 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  TabItem(label: string, idx: number): void {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(this.activeTab === idx ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeTab === idx ? '#1A73E8' : '#5F6368')
        .margin({ top: 8 })
      // 下划线激活态
      Row()
        .width(idx === 0 ? 40 : 48)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.activeTab === idx ? '#1A73E8' : '#FFFFFF')
        .margin({ top: 6, bottom: 4 })
    }
    .margin({ right: 18 })
    .onClick(() => {
      this.activeTab = idx
      console.info('[SessionPlayer] tab switch -> ' + idx)
    })
  }

  @Builder
  PlaybackControls(): void {
    Column() {
      Row() {
        Button(this.isPlaying ? '暂停' : '播放')
          .fontSize(14)
          .width(80)
          .onClick(() => {
            if (this.replayer) {
              if (this.isPlaying) {
                this.replayer.pause()
                this.isPlaying = false
              } else {
                this.replayer.play()
                this.isPlaying = true
              }
            }
          })

        Button('停止')
          .fontSize(14)
          .width(80)
          .margin({ left: 8 })
          .onClick(() => {
            if (this.replayer) {
              this.replayer.stop()
              this.isPlaying = false
              this.currentTime = 0
              this.updateCurrentView()
            }
          })

        Row() {
          ForEach(Constants.REPLAY_SPEEDS, (sp: number) => {
            Button(`${sp}x`)
              .fontSize(12)
              .height(28)
              .backgroundColor(sp === this.speed ? '#007DFF' : '#EEEEEE')
              .fontColor(sp === this.speed ? '#FFFFFF' : '#333333')
              .margin({ left: 4 })
              .onClick(() => {
                this.speed = sp
                if (this.replayer) {
                  this.replayer.setSpeed(sp)
                }
              })
          })
        }
        .margin({ left: 8 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 8, bottom: 8 })

      // P15: Slider 与操作节点标记叠层（标记按时间百分比定位，点击跳转该步）
      Stack({ alignContent: Alignment.Start }) {
        Slider({
          value: this.currentTime,
          min: 0,
          max: this.session?.duration || 1,
          step: 100
        })
          .width('100%')
          .onChange((value: number) => {
            if (this.replayer) {
              this.replayer.seekTo(value)
              this.currentTime = value
              this.updateCurrentView()
            }
          })

        ForEach(this.marks, (mk: TimelineMark) => {
          Column() {
            Circle({ width: 5, height: 5 })
              .fill('#007DFF')
          }
          .width(16)
          .height(16)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .position({ x: `${mk.pct}%`, y: 16 })
          .onClick(() => {
            if (this.replayer) {
              this.replayer.seekTo(Math.max(0, mk.time))
              this.currentTime = Math.max(0, mk.time)
              this.updateCurrentView()
              console.info('[SessionPlayer] mark jump -> ' + mk.time + 'ms')
            }
          })
        }, (mk: TimelineMark) => mk.key)
      }
      .width('90%')
      .height(40)
      .margin({ top: 2, bottom: 2 })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor('#F5F5F5')
  }

  /** P25b: 标签页视图 —— 该会话涉及的 URL 去重列表(如实展示,无 tab 结构数据) */
  @Builder
  TabsView(): void {
    Column() {
      Text('会话标签页')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ top: 8, bottom: 4 })

      if (this.tabUrls.length === 0) {
        Text('本会话未记录标签页数据')
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 20 })
      } else {
        List() {
          ForEach(this.tabUrls, (url: string) => {
            ListItem() {
              Row() {
                Circle({ width: 6, height: 6 })
                  .fill('#1A73E8')
                  .margin({ right: 8 })
                Text(url)
                  .fontSize(12)
                  .fontColor('#333333')
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
            }
          }, (url: string) => url)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor('#F8F8F8')
  }

  @Builder
  OperationTimeline(): void {
    Column() {
      Text('操作时间线')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ top: 8, bottom: 4 })

      List() {
        ForEach(this.operationLogs, (log: OperationLog) => {
          ListItem() {
            Row() {
              // P15: 操作类型图标（navigate/click/type/scroll/snapshot/wait 分形）
              Image(this.opIcon(log.operationType))
                .width(16)
                .height(16)
                .fillColor('#007DFF')
                .margin({ right: 6 })

              Text(this.formatTime(log.timestamp))
                .fontSize(10)
                .fontColor('#999999')
                .width(76)

              Text(log.operationType)
                .fontSize(12)
                .fontColor('#007DFF')
                .width(76)

              Text(log.targetElement)
                .fontSize(12)
                .fontColor('#333333')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(log.result)
                .fontSize(10)
                .fontColor(log.result === 'success' ? '#4CAF50' : '#F44336')
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              // P15: 点击步骤跳转到对应回放位置
              if (this.replayer && this.session) {
                const rel = Math.max(0, log.timestamp - this.session.startTime)
                this.replayer.seekTo(rel)
                this.currentTime = rel
                this.updateCurrentView()
              }
            })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#F8F8F8')
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    const minutes = date.getMinutes().toString().padStart(2, '0')
    const seconds = date.getSeconds().toString().padStart(2, '0')
    return `${minutes}:${seconds}`
  }
}
