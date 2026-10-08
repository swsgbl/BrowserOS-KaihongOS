import { TabInfo } from '../model/TabInfo'

@Component
export struct TabBar {
  @State tabs: TabInfo[] = []
  @State activeTabId: string = ''
  onTabSwitch?: (tabId: string) => void
  onTabClose?: (tabId: string) => void
  onTabCreate?: () => void

  build(): void {
    Row() {
      ForEach(this.tabs, (tab: TabInfo) => {
        Row() {
          Text(tab.title || '新标签页')
            .fontSize(12)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .fontColor(tab.tabId === this.activeTabId ? '#007DFF' : '#333333')

          if (tab.tabId === this.activeTabId) {
            Circle()
              .width(6)
              .height(6)
              .fill('#007DFF')
              .margin({ left: 4 })
          }

          Button({ type: ButtonType.Normal }) {
            Image($r('app.media.ic_close'))
              .width(12).height(12)
              .fillColor('#666666')
              .draggable(false)
              .fontSize(14)
              .fontColor('#999999')
          }
          .width(20)
          .height(20)
          .onClick(() => {
            if (this.onTabClose) {
              this.onTabClose(tab.tabId)
            }
          })
        }
        .padding({ left: 8, right: 4 })
        .height(32)
        .borderRadius(4)
        .backgroundColor(tab.tabId === this.activeTabId ? '#E6F2FF' : '#FFFFFF')
        .onClick(() => {
          if (this.onTabSwitch) {
            this.onTabSwitch(tab.tabId)
          }
        })
      })

      Button({ type: ButtonType.Normal }) {
        Text('+')
          .fontSize(16)
          .fontColor('#666666')
      }
      .width(32)
      .height(32)
      .onClick(() => {
        if (this.onTabCreate) {
          this.onTabCreate()
        }
      })
    }
    .width('100%')
    .height(36)
    .padding({ left: 4, right: 4 })
    .backgroundColor('#F0F0F0')
  }
}