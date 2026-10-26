import { ConnectionManager } from '../service/ConnectionManager'
import { I18n } from '../common/I18n'
import { LoginStateManager } from '../service/LoginStateManager'
import { ConfigManager } from '../storage/ConfigManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { AppConfigUpdate } from '../model/AppConfig'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'

@Entry
@Component
struct OnboardingPage {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  /** p16c: AppStorage darkMode */
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @State currentStep: number = 0
  @State totalSteps: number = 5
  @State detectedTools: string[] = []
  @State connectedTools: string[] = []
  @State importedDomains: string[] = []
  @State isImporting: boolean = false

  aboutToAppear(): void {
    this.detectedTools = ConnectionManager.detectInstalledTools().map(t => t.displayName)
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('OnboardingPage theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Column() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }

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
    .backgroundColor(this.pal().surface)
    .padding({ left: 24, right: 24 })
  }

  @Builder
  StepIndicator(): void {
    Row() {
      ForEach([0, 1, 2, 3, 4], (step: number) => {
        Circle()
          .width(step === this.currentStep ? 12 : 8)
          .height(step === this.currentStep ? 12 : 8)
          .fill(step <= this.currentStep ? this.pal().accent : this.pal().border)
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
      Text(I18n.t('obWelcome'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .margin({ top: 40 })

      Text(I18n.t('obSubtitle'))
        .fontSize(16)
        .fontColor(this.pal().text2)
        .margin({ top: 12 })

      Text(I18n.t('obIntro'))
        .fontSize(14)
        .fontColor(this.pal().text2)
        .margin({ top: 24 })
        .textAlign(TextAlign.Center)

      Column() {
        Text(I18n.t('obFeatures'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text)
          .margin({ bottom: 8 })

        this.FeatureRow(I18n.t('obFeat1'))
        this.FeatureRow(I18n.t('obFeat2'))
        this.FeatureRow(I18n.t('obFeat3'))
        this.FeatureRow(I18n.t('obFeat4'))
        this.FeatureRow(I18n.t('obFeat5'))
      }
      .margin({ top: 32 })
      .padding(16)
      .borderRadius(8)
      .backgroundColor(this.pal().surfaceAlt)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  AIToolConnectStep(): void {
    Column() {
      Text(I18n.t('obConnectTools'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .margin({ top: 20 })

      Text(I18n.t('obConnectDesc'))
        .fontSize(14)
        .fontColor(this.pal().text2)
        .margin({ top: 12 })

      if (this.detectedTools.length === 0) {
        Column() {
          Text(I18n.t('obNoTools'))
            .fontSize(14)
            .fontColor(this.pal().text2)
            .margin({ top: 24 })

          Text(I18n.t('obInstallFirst'))
            .fontSize(12)
            .fontColor(this.pal().text2)
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(24)
        .borderRadius(8)
        .backgroundColor(this.pal().surfaceAlt)
        .margin({ top: 16 })
      } else {
        List() {
          ForEach(this.detectedTools, (tool: string) => {
            ListItem() {
              Row() {
                Text(tool)
                  .fontSize(14)
                  .fontColor(this.pal().text)
                  .layoutWeight(1)

                if (this.connectedTools.includes(tool)) {
                  Text(I18n.t('obConnected'))
                    .fontSize(12)
                    .fontColor('#4CAF50')
                } else {
                  Button(I18n.t('obConnectBtn'))
                    .fontSize(12)
                    .height(28)
                    .backgroundColor(this.pal().accent)
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
              .backgroundColor(this.pal().surfaceAlt)
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
      Text(I18n.t('obImportLoginTitle'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .margin({ top: 20 })

      Text(I18n.t('obImportDesc'))
        .fontSize(14)
        .fontColor(this.pal().text2)
        .margin({ top: 12 })

      if (this.isImporting) {
        LoadingProgress()
          .width(48)
          .height(48)
          .margin({ top: 24 })

        Text(I18n.t('obImporting'))
          .fontSize(14)
          .fontColor(this.pal().text2)
          .margin({ top: 8 })
      } else if (this.importedDomains.length > 0) {
        Text(`${I18n.t('obImportedN')}${this.importedDomains.length}${I18n.t('obImportedEnd')}`)
          .fontSize(14)
          .fontColor('#4CAF50')
          .margin({ top: 16 })

        List() {
          ForEach(this.importedDomains, (domain: string) => {
            ListItem() {
              Text(domain)
                .fontSize(12)
                .fontColor(this.pal().text)
                .padding(8)
            }
          })
        }
        .width('100%')
        .height(120)
        .margin({ top: 8 })
      } else {
        Button(I18n.t('obImportChromeBtn'))
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
      Text(I18n.t('obDemo'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .margin({ top: 20 })

      Text(I18n.t('obDemoDesc'))
        .fontSize(14)
        .fontColor(this.pal().text2)
        .margin({ top: 12 })

      Column() {
        Text(I18n.t('obDemo1'))
          .fontSize(14)
          .fontColor(this.pal().text)
          .margin({ bottom: 8 })
        Text(I18n.t('obDemo1d'))
          .fontSize(12)
          .fontColor(this.pal().text2)
          .margin({ bottom: 12 })

        Text(I18n.t('obDemo2'))
          .fontSize(14)
          .fontColor(this.pal().text)
          .margin({ bottom: 8 })
        Text(I18n.t('obDemo2d'))
          .fontSize(12)
          .fontColor(this.pal().text2)
          .margin({ bottom: 12 })

        Text(I18n.t('obDemo3'))
          .fontSize(14)
          .fontColor(this.pal().text)
          .margin({ bottom: 8 })
        Text(I18n.t('obDemo3d'))
          .fontSize(12)
          .fontColor(this.pal().text2)
          .margin({ bottom: 12 })

        Text(I18n.t('obDemo4'))
          .fontSize(14)
          .fontColor(this.pal().text)
          .margin({ bottom: 8 })
        Text(I18n.t('obDemo4d'))
          .fontSize(12)
          .fontColor(this.pal().text2)
      }
      .margin({ top: 24 })
      .padding(16)
      .borderRadius(8)
      .backgroundColor(this.pal().surfaceAlt)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  CompleteStep(): void {
    Column() {
      Text(I18n.t('obSetupDone'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#4CAF50')
        .margin({ top: 40 })

      Text(I18n.t('obReady'))
        .fontSize(16)
        .fontColor(this.pal().text)
        .margin({ top: 12 })

      Text(I18n.t('obReadyDesc'))
        .fontSize(14)
        .fontColor(this.pal().text2)
        .margin({ top: 8 })

      Button(I18n.t('obStart'))
        .fontSize(16)
        .width(200)
        .height(48)
        .backgroundColor(this.pal().accent)
        .margin({ top: 32 })
        .onClick(() => {
          const updateData: AppConfigUpdate = { isOnboardingCompleted: true }
          ConfigManager.update(updateData)
          console.info('OnboardingPage completed, entering BrowserShell')
          router.replaceUrl({ url: 'pages/BrowserShell' })
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  /** P11e: 功能列表行 —— SVG check 图标替代文字圆点 */
  @Builder
  FeatureRow(text: string): void {
    Row() {
      Image($rawfile('ic_check.svg'))
        .width(14).height(14)
        .fillColor('#4CAF50')
        .draggable(false)
        .margin({ right: 6 })
      Text(text)
        .fontSize(12)
        .fontColor(this.pal().text2)
    }
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 4 })
    .alignSelf(ItemAlign.Start)
  }

  @Builder
  NavigationButtons(): void {
    Row() {
      if (this.currentStep > 0) {
        Button(I18n.t('obPrev'))
          .fontSize(14)
          .width(100)
          .backgroundColor(this.pal().surfaceInput)
          .fontColor(this.pal().text)
          .onClick(() => {
            this.currentStep--
          })
      }

      if (this.currentStep < this.totalSteps - 1) {
        Button(I18n.t('obNext'))
          .fontSize(14)
          .width(100)
          .backgroundColor(this.pal().accent)
          .margin({ left: 12 })
          .onClick(() => {
            this.currentStep++
          })

        Button(I18n.t('obSkip'))
          .fontSize(14)
          .width(80)
          .backgroundColor(this.pal().surfaceInput)
          .fontColor(this.pal().text2)
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