import { ConnectionManager } from '../service/ConnectionManager'

@Component
export struct ConnectionPanel {
  @State detectedTools: string[] = []
  @State connectedTools: string[] = []
  @State connectionStatus: Record<string, string> = {}

  aboutToAppear(): void {
    this.refreshTools()
  }

  private refreshTools(): void {
    const detected = ConnectionManager.detectInstalledTools()
    this.detectedTools = detected.map(t => t.displayName)
    this.connectedTools = ConnectionManager.getConnectedTools().map(t => t.displayName)
  }

  build(): void {
    Column() {
      Text('AI工具连接')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 8 })

      if (this.detectedTools.length === 0) {
        Column() {
          Text('未检测到已安装的AI工具')
            .fontSize(12)
            .fontColor('#999999')

          Text('请先安装 Claude Code、Codex 或 Cursor')
            .fontSize(10)
            .fontColor('#BBBBBB')
            .margin({ top: 4 })
        }
        .padding(12)
        .borderRadius(8)
        .backgroundColor('#F8F8F8')
      } else {
        ForEach(this.detectedTools, (tool: string) => {
          Row() {
            Text(tool)
              .fontSize(12)
              .fontColor('#333333')
              .layoutWeight(1)

            if (this.connectedTools.includes(tool)) {
              Text('已连接')
                .fontSize(10)
                .fontColor('#4CAF50')
            } else {
              Button('连接')
                .fontSize(10)
                .height(24)
                .backgroundColor('#007DFF')
                .onClick(() => {
                  const toolName = this.getToolNameByDisplayName(tool)
                  if (toolName) {
                    ConnectionManager.connect(toolName)
                    this.refreshTools()
                  }
                })
            }
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor('#FFFFFF')
          .margin({ bottom: 4 })
        })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor('#F8F8F8')
  }

  private getToolNameByDisplayName(displayName: string): string | null {
    const tools = ConnectionManager.detectInstalledTools()
    const tool = tools.find(t => t.displayName === displayName)
    return tool?.name || null
  }
}