import { ConnectionManager } from '../service/ConnectionManager'
import { LoginStateManager } from '../service/LoginStateManager'
import { ConfigManager } from '../storage/ConfigManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { AppConfigUpdate } from '../model/AppConfig'

@Entry
@Component
struct OnboardingPage {
  @State currentStep: number = 0
  @State totalSteps: number = 5
  @State detectedTools: string[] = []
  @State connectedTools: string[] = []
  @State importedDomains: string[] = []
  @State isImporting: boolean = false

  aboutToAppear(): void {
    this.detectedTools = ConnectionManager.detectInstalledTools().map(t => t.displayName)
  }

  build(): void {
    Column() {
      this.StepIndicator()

      if (this.currentStep === 0) {
        this.WelcomeStep()
      } else if (this.currentStep === 1) {
        this.AIToolConnectStep()
      } else if (this.currentStep === 2) {
        this.LoginImportStep()
      } else if (this.currentStep === 3) {
        this.DemoStep()
      } else if (this.currentStep === 4) {
        this.CompleteStep()
      }

      this.NavigationButtons()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .padding({ left: 24, right: 24 })
  }

  @Builder
  StepIndicator(): void {
    Row() {
      ForEach([0, 1, 2, 3, 4], (step: number) => {
        Circle()
          .width(step === this.currentStep ? 12 : 8)
          .height(step === this.currentStep ? 12 : 8)
          .fill(step <= this.currentStep ? '#007DFF' : '#CCCCCC')
          .margin({ left: 4, right: 4 })
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 24, bottom: 24 })
  }

  @Builder
  WelcomeStep(): void {
    Column() {
      Text('欢迎使用 BrowserOS KaihongOS')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ top: 40 })

      Text('AI代理浏览器 - 深开鸿版本')
        .fontSize(16)
        .fontColor('#666666')
        .margin({ top: 12 })

      Text('让AI代理使用你已登录的账户浏览网页，并行运行多个代理，实时监控和回放每个会话。')
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 24 })
        .textAlign(TextAlign.Center)

      Column() {
        Text('核心功能:')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .margin({ bottom: 8 })

        Text('• AI代理驱动浏览器，使用你的真实登录状态')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 4 })
        Text('• 并行运行多个代理，各自独立标签页')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 4 })
        Text('• 实时仪表盘监控，会话录制与回放')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 4 })
        Text('• MCP协议兼容，支持Claude Code/Codex/Cursor')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 4 })
        Text('• 本地运行，隐私优先，数据不离机')
          .fontSize(12)
          .fontColor('#666666')
      }
      .margin({ top: 32 })
      .padding(16)
      .borderRadius(8)
      .backgroundColor('#F8F8F8')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  AIToolConnectStep(): void {
    Column() {
      Text('连接AI工具')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ top: 20 })

      Text('BrowserOS会自动检测本地已安装的AI工具，一键连接即可使用。')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 12 })

      if (this.detectedTools.length === 0) {
        Column() {
          Text('未检测到已安装的AI工具')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 24 })

          Text('请先安装 Claude Code、Codex 或 Cursor')
            .fontSize(12)
            .fontColor('#BBBBBB')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(24)
        .borderRadius(8)
        .backgroundColor('#F8F8F8')
        .margin({ top: 16 })
      } else {
        List() {
          ForEach(this.detectedTools, (tool: string) => {
            ListItem() {
              Row() {
                Text(tool)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)

                if (this.connectedTools.includes(tool)) {
                  Text('已连接')
                    .fontSize(12)
                    .fontColor('#4CAF50')
                } else {
                  Button('连接')
                    .fontSize(12)
                    .height(28)
                    .backgroundColor('#007DFF')
                    .onClick(() => {
                      const toolName = this.getToolNameByDisplayName(tool)
                      if (toolName) {
                        ConnectionManager.connect(toolName)
                        this.connectedTools = ConnectionManager.getConnectedTools().map(t => t.displayName)
                      }
                    })
                }
              }
              .width('100%')
              .padding(12)
              .borderRadius(8)
              .backgroundColor('#F8F8F8')
            }
          })
        }
        .width('100%')
        .margin({ top: 16 })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  LoginImportStep(): void {
    Column() {
      Text('导入登录状态')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ top: 20 })

      Text('一键导入Chrome的登录状态，让AI代理使用你的真实账户。')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 12 })

      if (this.isImporting) {
        LoadingProgress()
          .width(48)
          .height(48)
          .margin({ top: 24 })

        Text('正在导入...')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ top: 8 })
      } else if (this.importedDomains.length > 0) {
        Text(`已导入 ${this.importedDomains.length} 个网站的登录状态`)
          .fontSize(14)
          .fontColor('#4CAF50')
          .margin({ top: 16 })

        List() {
          ForEach(this.importedDomains, (domain: string) => {
            ListItem() {
              Text(domain)
                .fontSize(12)
                .fontColor('#333333')
                .padding(8)
            }
          })
        }
        .width('100%')
        .height(120)
        .margin({ top: 8 })
      } else {
        Button('导入Chrome登录状态')
          .fontSize(14)
          .width(200)
          .backgroundColor('#FF9800')
          .margin({ top: 24 })
          .onClick(async () => {
            this.isImporting = true
            const states = await LoginStateManager.importFromChrome()
            this.isImporting = false
            this.importedDomains = LoginStateManager.getImportedDomains()
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  DemoStep(): void {
    Column() {
      Text('功能演示')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ top: 20 })

      Text('以下是BrowserOS KaihongOS的核心功能演示：')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 12 })

      Column() {
        Text('1. AI代理浏览网页')
          .fontSize(14)
          .fontColor('#333333')
          .margin({ bottom: 8 })
        Text('   代理在独立标签页中自动浏览网页，执行点击、输入等操作')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 12 })

        Text('2. 实时仪表盘')
          .fontSize(14)
          .fontColor('#333333')
          .margin({ bottom: 8 })
        Text('   新标签页展示所有代理的实时工作状态')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 12 })

        Text('3. 会话回放')
          .fontSize(14)
          .fontColor('#333333')
          .margin({ bottom: 8 })
        Text('   每个会话自动录制，可随时回放查看代理操作过程')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ bottom: 12 })

        Text('4. MCP协议')
          .fontSize(14)
          .fontColor('#333333')
          .margin({ bottom: 8 })
        Text('   10个标准工具：navigate/click/type/screenshot/snapshot等')
          .fontSize(12)
          .fontColor('#666666')
      }
      .margin({ top: 24 })
      .padding(16)
      .borderRadius(8)
      .backgroundColor('#F8F8F8')
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  CompleteStep(): void {
    Column() {
      Text('设置完成!')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#4CAF50')
        .margin({ top: 40 })

      Text('BrowserOS KaihongOS 已准备就绪')
        .fontSize(16)
        .fontColor('#333333')
        .margin({ top: 12 })

      Text('现在你可以开始使用AI代理浏览网页了')
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 8 })

      Button('开始使用')
        .fontSize(16)
        .width(200)
        .height(48)
        .backgroundColor('#007DFF')
        .margin({ top: 32 })
        .onClick(() => {
          const updateData: AppConfigUpdate = { isOnboardingCompleted: true }
          ConfigManager.update(updateData)
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  NavigationButtons(): void {
    Row() {
      if (this.currentStep > 0) {
        Button('上一步')
          .fontSize(14)
          .width(100)
          .backgroundColor('#EEEEEE')
          .fontColor('#333333')
          .onClick(() => {
            this.currentStep--
          })
      }

      if (this.currentStep < this.totalSteps - 1) {
        Button('下一步')
          .fontSize(14)
          .width(100)
          .backgroundColor('#007DFF')
          .margin({ left: 12 })
          .onClick(() => {
            this.currentStep++
          })

        Button('跳过')
          .fontSize(14)
          .width(80)
          .backgroundColor('#EEEEEE')
          .fontColor('#666666')
          .margin({ left: 8 })
          .onClick(() => {
            this.currentStep++
          })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)

    .padding({ top: 16, bottom: 16 })
  }

  private getToolNameByDisplayName(displayName: string): string | null {
    const tools = ConnectionManager.detectInstalledTools()
    const tool = tools.find(t => t.displayName === displayName)
    return tool?.name || null
  }
}