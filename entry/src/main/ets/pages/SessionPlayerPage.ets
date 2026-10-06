import { SessionManager, SessionReplayer } from '../service/SessionManager'
import { SessionRecord, ScreenshotEntry, OperationLog } from '../model/SessionRecord'
import { Constants } from '../common/Constants'
import { router } from '@kit.ArkUI'

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
    }
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

      this.OperationTimeline()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
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

      Slider({
        value: this.currentTime,
        min: 0,
        max: this.session?.duration || 1,
        step: 100
      })
        .width('90%')
        .onChange((value: number) => {
          if (this.replayer) {
            this.replayer.seekTo(value)
            this.currentTime = value
            this.updateCurrentView()
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor('#F5F5F5')
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
              Text(this.formatTime(log.timestamp))
                .fontSize(10)
                .fontColor('#999999')
                .width(80)

              Text(log.operationType)
                .fontSize(12)
                .fontColor('#007DFF')
                .width(80)

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
          }
        })
      }
      .width('100%')
      .height(120)
    }
    .width('100%')
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