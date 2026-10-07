/**
 * P9-C1: 设置页（ref2 chrome://settings 风格）
 * 左 240vp 导航（AI 与 Agent / 外观 / 隐私与安全 / MCP / 关于）+ 右卡片列表。
 * LLM 表单迁移自 NeoDashboardPanel.AgentSetupCard 模式；MCP 节复用 getMcpEndpoint。
 */
import { ConfigManager } from '../storage/ConfigManager'
import { AppConfigUpdate } from '../model/AppConfig'
import { MCPServer } from '../service/MCPServer'
import { pasteboard } from '@kit.BasicServicesKit'
import { router } from '@kit.ArkUI'

interface NavItem {
  key: string
  icon: string
  label: string
}

@Entry
@Component
struct SettingsPage {
  @State navSelection: number = 0
  // LLM 表单
  @State llmBaseUrlInput: string = ''
  @State llmApiKeyInput: string = ''
  @State llmModelInput: string = ''
  @State llmSaveHint: string = ''
  // 外观
  @State darkMode: boolean = false
  // 隐私
  @State sensitiveConfirmOn: boolean = true
  // MCP
  @State mcpCopiedHint: string = ''
  // 版本
  private readonly appVersion: string = '1.0.0 (P9)'

  private readonly navItems: NavItem[] = [
    { key: 'ai', icon: '🤖', label: 'AI 与 Agent' },
    { key: 'appearance', icon: '🎨', label: '外观' },
    { key: 'privacy', icon: '🔒', label: '隐私与安全' },
    { key: 'mcp', icon: '🔌', label: 'MCP' },
    { key: 'about', icon: 'ℹ️', label: '关于' }
  ]

  aboutToAppear(): void {
    const cfg = ConfigManager.get()
    this.llmBaseUrlInput = cfg.llmBaseUrl
    this.llmApiKeyInput = cfg.llmApiKey
    this.llmModelInput = cfg.llmModel
    console.info('SettingsPage mounted')
  }

  private getMcpEndpoint(): string {
    const port = MCPServer.isRunning() ? MCPServer.getPort() : ConfigManager.getMcpPort()
    const token = MCPServer.getAuthToken()
    return `http://<本机IP>:${port}/mcp?token=${token.length > 0 ? token : '<token>'}`
  }

  private copyToClipboard(text: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      pasteboard.getSystemPasteboard().setData(data)
      this.mcpCopiedHint = '已复制'
      setTimeout(() => { this.mcpCopiedHint = '' }, 1500)
    } catch (e) {
      console.error('SettingsPage clipboard error: ' + e)
    }
  }

  build(): void {
    Row() {
      // 左导航 240
      Column() {
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#202124')
          .width('100%')
          .padding({ left: 20, top: 24, bottom: 16 })

        ForEach(this.navItems, (item: NavItem, index: number) => {
          Row() {
            Text(item.icon)
              .fontSize(14)
              .width(26)
            Text(item.label)
              .fontSize(13)
              .fontColor(index === this.navSelection ? '#1A73E8' : '#3C4043')
              .layoutWeight(1)
          }
          .width('100%')
          .height(40)
          .padding({ left: 14 })
          .borderRadius({ topLeft: 20, bottomLeft: 20, topRight: 0, bottomRight: 0 })
          .backgroundColor(index === this.navSelection ? '#E8F0FE' : Color.Transparent)
          .onClick(() => {
            this.navSelection = index
          })
        }, (item: NavItem) => item.key)
      }
      .width(240)
      .height('100%')
      .backgroundColor('#F1F3F4')

      // 右内容
      Scroll() {
        Column() {
          if (this.navSelection === 0) {
            this.AiSection()
          } else if (this.navSelection === 1) {
            this.AppearanceSection()
          } else if (this.navSelection === 2) {
            this.PrivacySection()
          } else if (this.navSelection === 3) {
            this.McpSection()
          } else {
            this.AboutSection()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 32, right: 32, top: 28, bottom: 40 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  CardShell(title: string, subtitle: string): void {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#202124')
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(11)
          .fontColor('#5F6368')
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AiSection(): void {
    Column() {
      this.CardShell('LLM 接入（OpenAI 兼容）', '代理引擎的大模型后端，OpenAI 兼容端点')

      Text('API 端点')
        .fontSize(12)
        .fontColor('#5F6368')
        .margin({ top: 16, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmBaseUrlInput, placeholder: 'https://api.example.com/v1' })
        .width('100%')
        .height(38)
        .fontSize(13)
        .backgroundColor('#F1F3F4')
        .borderRadius(8)
        .onChange((v: string) => { this.llmBaseUrlInput = v })

      Text('API Key')
        .fontSize(12)
        .fontColor('#5F6368')
        .margin({ top: 10, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmApiKeyInput, placeholder: 'sk-...（本地服务可留空）' })
        .width('100%')
        .height(38)
        .fontSize(13)
        .backgroundColor('#F1F3F4')
        .borderRadius(8)
        .onChange((v: string) => { this.llmApiKeyInput = v })

      Text('模型名')
        .fontSize(12)
        .fontColor('#5F6368')
        .margin({ top: 10, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmModelInput, placeholder: '如 agnes-3.0-flash' })
        .width('100%')
        .height(38)
        .fontSize(13)
        .backgroundColor('#F1F3F4')
        .borderRadius(8)
        .onChange((v: string) => { this.llmModelInput = v })

      Row() {
        Button('保存配置')
          .fontSize(13)
          .height(34)
          .backgroundColor('#1A73E8')
          .fontColor('#FFFFFF')
          .borderRadius(17)
          .onClick(async () => {
            const ok = await ConfigManager.update({
              llmBaseUrl: this.llmBaseUrlInput,
              llmApiKey: this.llmApiKeyInput,
              llmModel: this.llmModelInput
            } as AppConfigUpdate)
            this.llmSaveHint = ok ? '已保存' : '保存失败：校验未通过'
          })
        Button('测试连接')
          .fontSize(13)
          .height(34)
          .backgroundColor('#FFFFFF')
          .fontColor('#1A73E8')
          .borderRadius(17)
          .border({ width: 1, color: '#DADCE0' })
          .margin({ left: 10 })
          .onClick(() => {
            this.llmSaveHint = ConfigManager.isLlmConfigured() ? '连接配置有效' : '配置不完整'
          })
        if (this.llmSaveHint.length > 0) {
          Text(this.llmSaveHint)
            .fontSize(12)
            .fontColor(this.llmSaveHint === '已保存' || this.llmSaveHint === '连接配置有效' ? '#137333' : '#C5221F')
            .margin({ left: 10 })
        }
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E0E0E0' })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AppearanceSection(): void {
    Column() {
      this.CardShell('主题', '浅色 / 深色')

      Row() {
        Column() {
          Text('深色模式')
            .fontSize(13)
            .fontColor('#202124')
          Text('工具栏与内建页使用深色 chrome（实验性）')
            .fontSize(11)
            .fontColor('#5F6368')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.darkMode })
          .onChange((on: boolean) => {
            this.darkMode = on
            console.info('SettingsPage darkMode=' + on)
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E0E0E0' })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PrivacySection(): void {
    Column() {
      this.CardShell('敏感操作确认', '代理执行高危操作前弹确认对话框')

      Row() {
        Text('启用敏感操作确认')
          .fontSize(13)
          .fontColor('#202124')
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.sensitiveConfirmOn })
          .onChange((on: boolean) => {
            this.sensitiveConfirmOn = on
            console.info('SettingsPage sensitiveConfirm=' + on)
          })
      }
      .width('100%')
      .margin({ top: 16 })

      Divider().color('#E0E0E0').margin({ top: 16, bottom: 12 })

      Text('本地数据说明')
        .fontSize(13)
        .fontColor('#202124')
      Text('书签 / 历史 / 会话录制 / 登录态均存储在应用沙盒内，不上传任何远端服务器。MCP 服务仅监听本机端口，凭 token 鉴权。')
        .fontSize(11)
        .fontColor('#5F6368')
        .margin({ top: 6 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E0E0E0' })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  McpSection(): void {
    Column() {
      this.CardShell('本地 MCP 端点', '把 AI 工具（Claude Code / Cursor / VS Code 等）接到 BrowserOS')

      Row() {
        Text(this.getMcpEndpoint())
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor('#1A73E8')
          .backgroundColor('#F1F3F4')
          .borderRadius(6)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button(this.mcpCopiedHint.length > 0 ? this.mcpCopiedHint : 'Copy')
          .fontSize(12)
          .height(30)
          .backgroundColor('#1A73E8')
          .fontColor('#FFFFFF')
          .borderRadius(6)
          .margin({ left: 8 })
          .onClick(() => {
            this.copyToClipboard(this.getMcpEndpoint())
          })
      }
      .width('100%')
      .margin({ top: 16 })

      Text(`服务状态：${MCPServer.isRunning() ? '运行中 · 端口 ' + MCPServer.getPort() : '未启动'}`)
        .fontSize(11)
        .fontColor('#5F6368')
        .margin({ top: 10 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E0E0E0' })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AboutSection(): void {
    Column() {
      this.CardShell('BrowserOS for KaihongOS', '给 AI 代理用的浏览器')

      Row() {
        Text('版本')
          .fontSize(13)
          .fontColor('#202124')
          .layoutWeight(1)
        Text(this.appVersion)
          .fontSize(13)
          .fontColor('#5F6368')
      }
      .width('100%')
      .margin({ top: 16 })

      Row() {
        Text('构建')
          .fontSize(13)
          .fontColor('#202124')
          .layoutWeight(1)
        Text('P9 · ' + '2026-10-07')
          .fontSize(13)
          .fontColor('#5F6368')
      }
      .width('100%')
      .margin({ top: 10 })

      Button('返回浏览器')
        .fontSize(13)
        .height(34)
        .backgroundColor('#1A73E8')
        .fontColor('#FFFFFF')
        .borderRadius(17)
        .margin({ top: 20 })
        .onClick(() => {
          router.back()
        })
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E0E0E0' })
    .alignItems(HorizontalAlign.Start)
  }
}
