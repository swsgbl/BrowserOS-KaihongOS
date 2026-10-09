/**
 * P9-C1: 设置页（ref2 chrome://settings 风格）
 * 左 240vp 导航（AI 与 Agent / 外观 / 隐私与安全 / MCP / 关于）+ 右卡片列表。
 * LLM 表单迁移自 NeoDashboardPanel.AgentSetupCard 模式；MCP 节复用 getMcpEndpoint。
 */
import { ConfigManager } from '../storage/ConfigManager'
import { AppConfigUpdate } from '../model/AppConfig'
import { MCPServer } from '../service/MCPServer'
import { LLMClient, LLMChatMessage } from '../service/LLMClient'
import { pasteboard } from '@kit.BasicServicesKit'
import { bundleManager } from '@kit.AbilityKit'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'
import { SearchEngine, SEARCH_ENGINES, getEngineById } from '../common/SearchEngines'

interface NavItem {
  key: string
  icon: Resource
  label: string
}

@Entry
@Component
struct SettingsPage {
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') darkMode: boolean = false

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @State navSelection: number = 0
  // LLM 表单
  @State llmBaseUrlInput: string = ''
  @State llmApiKeyInput: string = ''
  @State llmModelInput: string = ''
  @State llmSaveHint: string = ''
  @State llmTesting: boolean = false
  // 外观（darkMode 改由 @StorageProp 提供）
  // 隐私
  @State sensitiveConfirmOn: boolean = true
  // P18: 搜索引擎
  @State searchEngineId: string = 'google'
  @State showEnginePicker: boolean = false
  // MCP
  @State mcpCopiedHint: string = ''
  // 版本（P17b: 动态读取 app.json5 versionName，避免硬编码漂移）
  @State appVersion: string = ''

  private readonly navItems: NavItem[] = [
    { key: 'search', icon: $r('app.media.ic_search'), label: '搜索' },
    { key: 'ai', icon: $r('app.media.ic_robot'), label: 'AI 与 Agent' },
    { key: 'appearance', icon: $r('app.media.ic_public'), label: '外观' },
    { key: 'privacy', icon: $r('app.media.ic_lock'), label: '隐私与安全' },
    { key: 'mcp', icon: $r('app.media.ic_info'), label: 'MCP' },
    { key: 'about', icon: $r('app.media.ic_help'), label: '关于' }
  ]

  aboutToAppear(): void {
    const cfg = ConfigManager.get()
    this.llmBaseUrlInput = cfg.llmBaseUrl
    this.llmApiKeyInput = cfg.llmApiKey
    this.llmModelInput = cfg.llmModel
    this.sensitiveConfirmOn = ConfigManager.isSensitiveConfirm()
    this.searchEngineId = ConfigManager.getSearchEngineId()
    // P18: omnibox 「切换」入口深链 —— params.section === 'search' 直达搜索节
    const sp = router.getParams() as Record<string, Object>
    if (sp && sp['section'] === 'search') {
      this.navSelection = 0
    }
    // P17b: About 版本动态化 —— GET_BUNDLE_INFO_DEFAULT(0) 即含 versionName
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.appVersion = info.versionName
    } catch (e) {
      this.appVersion = 'dev'
      console.error('SettingsPage getBundleInfo fail: ' + e)
    }
    console.info('SettingsPage mounted version=' + this.appVersion)
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
        Image($r('app.media.ic_back'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
          .width(36)
          .height(40)
          .margin({ top: 8 })
          .onClick(() => {
            router.back()
          })
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .width('100%')
          .padding({ left: 20, top: 24, bottom: 16 })

        ForEach(this.navItems, (item: NavItem, index: number) => {
          Row() {
            Image(item.icon)
              .width(16).height(16)
              .fillColor(index === this.navSelection ? '#1A73E8' : this.pal().text2)
              .draggable(false)
              .margin({ right: 6 })
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
      .backgroundColor(this.pal().surfaceAlt)

      // 右内容
      Scroll() {
        Column() {
          if (this.navSelection === 0) {
            this.SearchSection()
          } else if (this.navSelection === 1) {
            this.AiSection()
          } else if (this.navSelection === 2) {
            this.AppearanceSection()
          } else if (this.navSelection === 3) {
            this.PrivacySection()
          } else if (this.navSelection === 4) {
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
      .backgroundColor(this.pal().surface)
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
        .fontColor(this.pal().text)
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** P18: 搜索引擎节 —— 当前引擎 + 单选切换列表（选中即保存生效） */
  @Builder
  SearchSection(): void {
    Column() {
      this.CardShell('搜索引擎', '地址栏输入非网址内容时，使用以下搜索引擎')

      Row() {
        Column() {
          Text(getEngineById(this.searchEngineId).name)
            .fontSize(13)
            .fontColor(this.pal().text)
          Text(getEngineById(this.searchEngineId).queryUrl)
            .fontSize(11)
            .fontColor(this.pal().text2)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.showEnginePicker ? '收起' : '更改')
          .fontSize(13)
          .height(32)
          .backgroundColor(this.pal().surface)
          .fontColor('#1A73E8')
          .borderRadius(16)
          .border({ width: 1, color: this.pal().border })
          .onClick(() => {
            this.showEnginePicker = !this.showEnginePicker
          })
      }
      .width('100%')
      .margin({ top: 16 })

      if (this.showEnginePicker) {
        Divider().color(this.pal().border).margin({ top: 14, bottom: 8 })
        ForEach(SEARCH_ENGINES, (e: SearchEngine) => {
          Row() {
            Column() {
              Text(e.name)
                .fontSize(13)
                .fontColor(this.pal().text)
              Text(e.desc + ' · ' + e.queryUrl)
                .fontSize(10)
                .fontColor(this.pal().text2)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 1 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (e.id === this.searchEngineId) {
              Image($r('app.media.ic_check'))
                .width(16).height(16)
                .fillColor('#1A73E8')
                .draggable(false)
            }
          }
          .width('100%')
          .height(44)
          .padding({ left: 10, right: 10 })
          .borderRadius(8)
          .backgroundColor(e.id === this.searchEngineId ? this.pal().selected : this.pal().surfaceAlt)
          .margin({ top: 4 })
          .onClick(() => {
            this.searchEngineId = e.id
            ConfigManager.update({ searchEngineId: e.id } as AppConfigUpdate)
            this.showEnginePicker = false
            console.info('SettingsPage searchEngine switched: ' + e.id)
          })
        }, (e: SearchEngine) => e.id)
      }
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AiSection(): void {
    Column() {
      this.CardShell('LLM 接入（OpenAI 兼容）', '代理引擎的大模型后端，OpenAI 兼容端点')

      Text('API 端点')
        .fontSize(12)
        .fontColor(this.pal().text2)
        .margin({ top: 16, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmBaseUrlInput, placeholder: 'https://api.example.com/v1' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(38)
        .fontSize(13)
        .backgroundColor(this.pal().surfaceAlt)
        .borderRadius(8)
        .onChange((v: string) => { this.llmBaseUrlInput = v })

      Text('API Key')
        .fontSize(12)
        .fontColor(this.pal().text2)
        .margin({ top: 10, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmApiKeyInput, placeholder: 'sk-...（本地服务可留空）' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(38)
        .fontSize(13)
        .backgroundColor(this.pal().surfaceAlt)
        .borderRadius(8)
        .onChange((v: string) => { this.llmApiKeyInput = v })

      Text('模型名')
        .fontSize(12)
        .fontColor(this.pal().text2)
        .margin({ top: 10, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmModelInput, placeholder: '如 agnes-3.0-flash' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(38)
        .fontSize(13)
        .backgroundColor(this.pal().surfaceAlt)
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
        Button(this.llmTesting ? '测试中…' : '测试连接')
          .fontSize(13)
          .height(34)
          .backgroundColor(this.pal().surface)
          .fontColor('#1A73E8')
          .borderRadius(17)
          .border({ width: 1, color: this.pal().border })
          .margin({ left: 10 })
          .enabled(!this.llmTesting)
          .onClick(async () => {
            const base = this.llmBaseUrlInput.trim()
            if (base.length === 0) {
              this.llmSaveHint = '请先填写 API 端点'
              return
            }
            this.llmTesting = true
            this.llmSaveHint = '测试中…'
            const t0 = Date.now()
            const resp = await LLMClient.chat({
              baseUrl: base,
              apiKey: this.llmApiKeyInput.trim(),
              model: this.llmModelInput.trim(),
              messages: [LLMChatMessage.user('ping')],
              tools: [],
              timeoutMs: 15000
            })
            const ms = Date.now() - t0
            this.llmTesting = false
            if (resp) {
              const m = this.llmModelInput.trim().length > 0 ? this.llmModelInput.trim() : 'default'
              this.llmSaveHint = `${m} 连接成功 (${ms}ms)`
              console.info('SettingsPage llm test OK: ' + m + ' ' + ms + 'ms')
            } else {
              this.llmSaveHint = (LLMClient.lastError.length > 0 ? LLMClient.lastError : '未知错误')
              console.warn('SettingsPage llm test FAIL: ' + LLMClient.lastError)
            }
          })
        if (this.llmSaveHint.length > 0) {
          Text(this.llmSaveHint)
            .fontSize(12)
            .fontColor((this.llmSaveHint === '已保存' || this.llmSaveHint.includes('连接成功')) ? (this.darkMode ? '#81C995' : '#137333') : (this.llmSaveHint.length === 0 ? this.pal().text2 : (this.darkMode ? '#F28B82' : '#C5221F')))
            .margin({ left: 10 })
        }
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
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
            .fontColor(this.pal().text)
          Text('工具栏、侧栏与内建页即时切换深色配色（Chrome 系色板）')
            .fontSize(11)
            .fontColor(this.pal().text2)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.darkMode })
          .onChange((on: boolean) => {
            this.darkMode = on
            AppStorage.setOrCreate('darkMode', on)
            ConfigManager.update({ darkMode: on } as AppConfigUpdate)
            console.info('SettingsPage darkMode=' + on)
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PrivacySection(): void {
    Column() {
      this.CardShell('敏感操作确认', '代理执行高危操作前弹确认对话框')

      Row() {
        Text('启用敏感操作确认')
          .fontSize(13)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.sensitiveConfirmOn })
          .onChange((on: boolean) => {
            this.sensitiveConfirmOn = on
            ConfigManager.update({ sensitiveConfirm: on } as AppConfigUpdate)
            console.info('SettingsPage sensitiveConfirm=' + on)
          })
      }
      .width('100%')
      .margin({ top: 16 })

      Divider().color(this.pal().border).margin({ top: 16, bottom: 12 })

      Text('本地数据说明')
        .fontSize(13)
        .fontColor(this.pal().text)
      Text('书签 / 历史 / 会话录制 / 登录态均存储在应用沙盒内，不上传任何远端服务器。MCP 服务仅监听本机端口，凭 token 鉴权。')
        .fontSize(11)
        .fontColor(this.pal().text2)
        .margin({ top: 6 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
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
          .backgroundColor(this.pal().surfaceAlt)
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
        .fontColor(this.pal().text2)
        .margin({ top: 10 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(12)
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AboutSection(): void {
    Column() {
      this.CardShell('BrowserOS for KaihongOS', '给 AI 代理用的浏览器')

      Row() {
        Text('版本')
          .fontSize(13)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Text(this.appVersion)
          .fontSize(13)
          .fontColor(this.pal().text2)
      }
      .width('100%')
      .margin({ top: 16 })

      Row() {
        Text('构建')
          .fontSize(13)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Text('KaihongOS · API 14')
          .fontSize(13)
          .fontColor(this.pal().text2)
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
    .backgroundColor(this.pal().surface)
    .border({ width: 1, color: this.pal().border })
    .alignItems(HorizontalAlign.Start)
  }
}
