import { SessionRecord } from '../model/SessionRecord'

@Component
export struct SessionList {
  @State sessions: SessionRecord[] = []
  @State searchKeyword: string = ''
  onSessionClick?: (sessionId: string) => void

  build(): void {
    Column() {
      TextInput({ placeholder: '搜索会话...' })
        .width('100%')
        .height(36)
        .onChange((value: string) => {
          this.searchKeyword = value
        })

      if (this.getFilteredSessions().length === 0) {
        Column() {
          Text('暂无历史会话')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.getFilteredSessions(), (session: SessionRecord) => {
            ListItem() {
              Row() {
                Column() {
                  Text(session.agentId.substring(0, 20))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333')

                  Text(this.formatTime(session.startTime))
                    .fontSize(10)
                    .fontColor('#999999')
                    .margin({ top: 4 })

                  Text(`${session.urlSequence.length} 个页面 · ${this.formatDuration(session.duration)}`)
                    .fontSize(10)
                    .fontColor('#666666')
                    .margin({ top: 2 })
                }
                .layoutWeight(1)

                if (session.isCorrupted) {
                  Text('损坏')
                    .fontSize(10)
                    .fontColor('#F44336')
                    .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                    .borderRadius(2)
                    .backgroundColor('#FFEBEE')
                }

                Button('回放')
                  .fontSize(10)
                  .height(24)
                  .backgroundColor('#007DFF')
                  .onClick(() => {
                    if (this.onSessionClick) {
                      this.onSessionClick(session.sessionId)
                    }
                  })
              }
              .width('100%')
              .padding(8)
              .borderRadius(4)
              .backgroundColor('#FFFFFF')
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
  }

  private getFilteredSessions(): SessionRecord[] {
    if (!this.searchKeyword) {
      return this.sessions
    }
    const keyword = this.searchKeyword.toLowerCase()
    return this.sessions.filter(s =>
      s.agentId.toLowerCase().includes(keyword) ||
      s.urlSequence.some(url => url.toLowerCase().includes(keyword))
    )
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()} ${date.getHours()}:${date.getMinutes()}`
  }

  private formatDuration(ms: number): string {
    const seconds = Math.floor(ms / 1000)
    const minutes = Math.floor(seconds / 60)
    if (minutes > 0) {
      return `${minutes}m ${seconds % 60}s`
    }
    return `${seconds}s`
  }
}