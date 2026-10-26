/**
 * P9-C1: 设置页（ref2 chrome://settings 风格）
 * 左 240vp 导航（AI 与 Agent / 外观 / 隐私与安全 / MCP / 关于）+ 右卡片列表。
 * LLM 表单迁移自 NeoDashboardPanel.AgentSetupCard 模式；MCP 节复用 getMcpEndpoint。
 */
import { ConfigManager } from '../storage/ConfigManager'
import { I18n } from '../common/I18n'
import { AppConfigUpdate } from '../model/AppConfig'
import { MCPServer } from '../service/MCPServer'
import { LLMClient, LLMChatMessage } from '../service/LLMClient'
import { pasteboard } from '@kit.BasicServicesKit'
import { bundleManager } from '@kit.AbilityKit'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'
import { SearchEngine, SEARCH_ENGINES, getEngineById } from '../common/SearchEngines'
import { HistoryManager } from '../service/HistoryManager'
import { BookmarkManager } from '../service/BookmarkManager'
import { LoginStateManager } from '../service/LoginStateManager'
import { DownloadManager } from '../service/DownloadManager'
import { SessionManager } from '../service/SessionManager'

interface NavItem {
  key: string
  icon: Resource
  label: string
}

@Entry
@Component
struct SettingsPage {
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip2') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip2(): void {
    this.localeVersion++
  }
  @State themeVersion: number = 0 // P44

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
  // P19b: 清除浏览数据
  @State clearShowConfirm: boolean = false
  @State clearDoneHint: string = ''
  @State cntHistory: number = 0
  @State cntBookmarks: number = 0
  @State cntLogins: number = 0
  @State cntDownloads: number = 0
  @State cntSessions: number = 0
  @State selHistory: boolean = true
  @State selBookmarks: boolean = false
  @State selLogins: boolean = false
  @State selDownloads: boolean = false
  // P18: 搜索引擎
  @State searchEngineId: string = 'google'
  @State showEnginePicker: boolean = false
  // MCP
  @State mcpCopiedHint: string = ''
  // 版本（P17b: 动态读取 app.json5 versionName，避免硬编码漂移）
  @State appVersion: string = ''

  private get navItems(): NavItem[] {
    return [
      { key: 'search', icon: $rawfile('ic_search.svg'), label: I18n.t('stTabSearch') },
      { key: 'ai', icon: $rawfile('ic_robot.svg'), label: I18n.t('stTabAI') },
      { key: 'appearance', icon: $rawfile('ic_public.svg'), label: I18n.t('stTabAppearance') },
      { key: 'privacy', icon: $rawfile('ic_lock.svg'), label: I18n.t('stTabPrivacy') },
      { key: 'mcp', icon: $rawfile('ic_info.svg'), label: 'MCP' },
      { key: 'about', icon: $rawfile('ic_help.svg'), label: I18n.t('stTabAbout') }
    ]
  }

  /** P19b: 刷新各类数据计数 */
  private refreshClearCounts(): void {
    this.cntHistory = HistoryManager.getAllHistory(9999).length
    this.cntBookmarks = BookmarkManager.getAllBookmarks().length
    this.cntLogins = LoginStateManager.getImportedDomains().length
    this.cntDownloads = DownloadManager.getDownloads().length
    this.cntSessions = SessionManager.getSessionList().length
    console.info('SettingsPage clear counts: hist=' + this.cntHistory + ' bm=' + this.cntBookmarks + ' login=' + this.cntLogins + ' dl=' + this.cntDownloads + ' sess=' + this.cntSessions)
  }

  /** P19b: 执行所选清除 */
  private doClearSelected(): void {
    if (this.selHistory) {
      HistoryManager.clearAllHistory()
      SessionManager.clearAllSessions()
    }
    if (this.selBookmarks) {
      BookmarkManager.clearAllBookmarks()
    }
    if (this.selLogins) {
      LoginStateManager.clearAll()
    }
    if (this.selDownloads) {
      DownloadManager.clearAllDownloads()
    }
    this.clearShowConfirm = false
    this.clearDoneHint = I18n.t('stCleared')
    console.info('SettingsPage clearSelected done')
    setTimeout(() => {
      this.refreshClearCounts()
    }, 300)
  }

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
      this.mcpCopiedHint = I18n.t('copied')
      setTimeout(() => { this.mcpCopiedHint = '' }, 1500)
    } catch (e) {
      console.error('SettingsPage clipboard error: ' + e)
    }
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('SettingsPage theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Row() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }
        // P48: localeVersion 渲染依赖锚
        if (this.localeVersion < 0) {
          Text('').fontSize(0)
        }

      // 左导航 240
      Column() {
        Image($rawfile('ic_back.svg'))
          .width(20).height(20)
          .fillColor(this.pal().text2)
          .draggable(false)
          .width(36)
          .height(40)
          .margin({ top: 8 })
          .onClick(() => {
            router.back()
          })
        Text(I18n.t('stTitle'))
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
      this.CardShell(I18n.t('stEngineCard'), I18n.t('stEngineDesc'))

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

        Button(this.showEnginePicker ? I18n.t('stCollapse') : I18n.t('stChange'))
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
              Image($rawfile('ic_check.svg'))
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
      this.CardShell(I18n.t('stLlmCard'), I18n.t('stLlmDesc'))

      Text(I18n.t('stApiEndpoint'))
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
      TextInput({ text: this.llmApiKeyInput, placeholder: I18n.t('stApiKeyPh') }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(38)
        .fontSize(13)
        .backgroundColor(this.pal().surfaceAlt)
        .borderRadius(8)
        .onChange((v: string) => { this.llmApiKeyInput = v })

      Text(I18n.t('stModelName'))
        .fontSize(12)
        .fontColor(this.pal().text2)
        .margin({ top: 10, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmModelInput, placeholder: I18n.t('stModelPh') }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(38)
        .fontSize(13)
        .backgroundColor(this.pal().surfaceAlt)
        .borderRadius(8)
        .onChange((v: string) => { this.llmModelInput = v })

      Row() {
        Button(I18n.t('saveConfig'))
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
            this.llmSaveHint = ok ? I18n.t('saved') : I18n.t('saveFailed')
          })
        Button(this.llmTesting ? I18n.t('testing') : I18n.t('stTestConnBtn'))
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
              this.llmSaveHint = I18n.t('stFillEndpoint')
              return
            }
            this.llmTesting = true
            this.llmSaveHint = I18n.t('testing')
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
              this.llmSaveHint = `${m}${I18n.t('stConnOk')}${ms}${I18n.t('stConnOkEnd')}`
              console.info('SettingsPage llm test OK: ' + m + ' ' + ms + 'ms')
            } else {
              this.llmSaveHint = (LLMClient.lastError.length > 0 ? LLMClient.lastError : I18n.t('unknownError'))
              console.warn('SettingsPage llm test FAIL: ' + LLMClient.lastError)
            }
          })
        if (this.llmSaveHint.length > 0) {
          Text(this.llmSaveHint)
            .fontSize(12)
            .fontColor((this.llmSaveHint === I18n.t('saved') || this.llmSaveHint.includes('连接成功') || this.llmSaveHint.includes('successful')) ? (this.darkMode ? '#81C995' : '#137333') : (this.darkMode ? '#F28B82' : '#C5221F'))
            .margin({ left: 10 })
        }
      }
      .width('100%')
      .margin({ top: 16 })

      // p23b: LLM Hub 入口（多供应商预设管理）
      Row() {
        Text(I18n.t('stManageProviders'))
          .fontSize(12)
          .fontColor('#1A73E8')
        Blank()
        Text('›')
          .fontSize(14)
          .fontColor(this.pal().text2)
      }
      .width('100%')
      .padding({ top: 10, bottom: 6 })
      .onClick(() => {
        router.pushUrl({ url: 'pages/LlmHubPage' })
      })
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
      this.CardShell(I18n.t('stThemeCard'), I18n.t('stThemeDesc'))

      Row() {
        Column() {
          Text(I18n.t('stDarkMode'))
            .fontSize(13)
            .fontColor(this.pal().text)
          Text(I18n.t('stDarkDesc'))
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

      // P48: 语言切换（中文 / English）
      Divider().color(this.pal().border).margin({ top: 16, bottom: 12 })
      Row() {
        Column() {
          Text(I18n.t('stLangCard'))
            .fontSize(13)
            .fontColor(this.pal().text)
          Text(I18n.t('stLangDesc'))
            .fontSize(11)
            .fontColor(this.pal().text2)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: 6 }) {
          Text(I18n.t('stLangZh'))
            .fontSize(13)
            .fontColor(this.appLocale === 'zh' ? '#1A73E8' : this.pal().text2)
            .onClick(() => {
              I18n.setLocale('zh')
            })
          Text('·')
            .fontSize(13)
            .fontColor(this.pal().text2)
          Text(I18n.t('stLangEn'))
            .fontSize(13)
            .fontColor(this.appLocale === 'en' ? '#1A73E8' : this.pal().text2)
            .onClick(() => {
              I18n.setLocale('en')
            })
        }
      }
      .width('100%')
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
      this.CardShell(I18n.t('stSensitiveCard'), I18n.t('stSensitiveDesc'))

      Row() {
        Text(I18n.t('stSensitiveEnable'))
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

      // P19b: 清除浏览数据卡片
      Row() {
        Text(I18n.t('stClearData'))
          .fontSize(13)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Button(I18n.t('stClearBtn'))
          .fontSize(12)
          .height(30)
          .backgroundColor('#D93025')
          .fontColor('#FFFFFF')
          .borderRadius(15)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.refreshClearCounts()
            this.clearShowConfirm = true
            console.info('SettingsPage clear confirm shown')
          })
      }
      .width('100%')
      .onAppear(() => {
        this.refreshClearCounts()
      })

      Column({ space: 6 }) {
        Row() {
          Checkbox().select(this.selHistory).selectedColor('#1A73E8')
            .onChange((v: boolean) => { this.selHistory = v })
            .width(18).height(18)
          Text(I18n.t('stBrowsingHistory'))
            .fontSize(12)
            .fontColor(this.pal().text)
            .layoutWeight(1)
          Text('' + this.cntHistory + I18n.t('ntCountEnd'))
            .fontSize(11)
            .fontColor(this.pal().text2)
        }.width('100%')
        Row() {
          Checkbox().select(this.selBookmarks).selectedColor('#1A73E8')
            .onChange((v: boolean) => { this.selBookmarks = v })
            .width(18).height(18)
          Text(I18n.t('stBookmarks'))
            .fontSize(12)
            .fontColor(this.pal().text)
            .layoutWeight(1)
          Text('' + this.cntBookmarks + I18n.t('ntCountEnd'))
            .fontSize(11)
            .fontColor(this.pal().text2)
        }.width('100%')
        Row() {
          Checkbox().select(this.selLogins).selectedColor('#1A73E8')
            .onChange((v: boolean) => { this.selLogins = v })
            .width(18).height(18)
          Text(I18n.t('stSavedLogins'))
            .fontSize(12)
            .fontColor(this.pal().text)
            .layoutWeight(1)
          Text(I18n.t('stDomainN').replace('{n}', '' + this.cntLogins))
            .fontSize(11)
            .fontColor(this.pal().text2)
        }.width('100%')
        Row() {
          Checkbox().select(this.selDownloads).selectedColor('#1A73E8')
            .onChange((v: boolean) => { this.selDownloads = v })
            .width(18).height(18)
          Text(I18n.t('stDownloadRecords'))
            .fontSize(12)
            .fontColor(this.pal().text)
            .layoutWeight(1)
          Text(I18n.t('stDownloadN').replace('{n}', '' + this.cntDownloads))
            .fontSize(11)
            .fontColor(this.pal().text2)
        }.width('100%')
      }
      .width('100%')
      .margin({ top: 10 })
      .alignItems(HorizontalAlign.Start)

      if (this.clearShowConfirm) {
        Row({ space: 10 }) {
          Text(I18n.t('stClearConfirm'))
            .fontSize(12)
            .fontColor(this.pal().text2)
            .layoutWeight(1)
          Button(I18n.t('cancel'))
            .fontSize(12).height(28)
            .backgroundColor(this.pal().surfaceAlt).fontColor(this.pal().text)
            .onClick(() => { this.clearShowConfirm = false })
          Button(I18n.t('stConfirmClear'))
            .fontSize(12).height(28)
            .backgroundColor('#D93025').fontColor('#FFFFFF')
            .onClick(() => { this.doClearSelected() })
        }
        .width('100%')
        .margin({ top: 10 })
      }

      if (this.clearDoneHint.length > 0) {
        Text(this.clearDoneHint)
          .fontSize(11)
          .fontColor('#1E8E3E')
          .margin({ top: 6 })
      }

      Divider().color(this.pal().border).margin({ top: 16, bottom: 12 })

      Text(I18n.t('stLocalDataNote'))
        .fontSize(13)
        .fontColor(this.pal().text)
      Text(I18n.t('stLocalDataDesc'))
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
      this.CardShell(I18n.t('stMcpCard'), I18n.t('stMcpDesc'))

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

      Text(I18n.t('stMcpStatus') + (MCPServer.isRunning() ? I18n.t('stMcpRunning') + MCPServer.getPort() : I18n.t('stMcpStopped')))
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
      this.CardShell(I18n.t('stAboutCard'), I18n.t('stAboutDesc'))

      Row() {
        Text(I18n.t('stVersion'))
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
        Text(I18n.t('stBuild'))
          .fontSize(13)
          .fontColor(this.pal().text)
          .layoutWeight(1)
        Text('KaihongOS · API 14')
          .fontSize(13)
          .fontColor(this.pal().text2)
      }
      .width('100%')
      .margin({ top: 10 })

      Button(I18n.t('stBackBrowser'))
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
