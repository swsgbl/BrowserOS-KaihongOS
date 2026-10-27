import { AgentEngine } from '../service/AgentEngine'
import { I18n } from '../common/I18n'
import { AgentStatusInfo } from '../model/AgentStatus'
import { AgentStatus, RunStrategy } from '../common/Types'
import { ConnectionManager } from '../service/ConnectionManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ConfigManager } from '../storage/ConfigManager'
import { AppConfigUpdate } from '../model/AppConfig'
import { TabManager } from '../service/TabManager'
import { MCPServer } from '../service/MCPServer'
import { SessionManager } from '../service/SessionManager'
import { SessionRecord } from '../model/SessionRecord'
import { pasteboard } from '@kit.BasicServicesKit'
import { preferences } from '@kit.ArkData'
import { router } from '@kit.ArkUI'
import { Palette } from '../common/Palette'
import { getEngineById } from '../common/SearchEngines'
/**
 * P8: 官网 UI 一比一复刻 —— NeoDashboardPanel 全面重排。
 * C1 新标签页 Cockpit：3 列磁贴网格（首块 2x 宽 hero 渐变卡）+ 深色页脚最近会话卡 + 空态。
 * C2 MCP Install Board：深灰 hero（端点 URL 等宽 + Copy/Docs）+ harness 网格 + Connect 弹 JSON。
 * 设计语言：chrome #F0F0F0 / 深色卡 #2D2D30 / 内容白 / hero 渐变 #2E6FE8→#8B5CF6 /
 * 状态点 红#C43E3E(运行) 绿#22A06B(完成) 蓝#2E6FE8(进行)。
 * 仅重排 UI 层，服务/引擎逻辑不动（P1-P7 已验收功能保持）。
 */

interface HarnessDesc {
  name: string
  desc: string
  logoBg: string
  logoText: string
}

/** P25a: MCP 连接器目录条目(对标上游 claw-app 46 家品牌图标目录) */
interface ConnectorItem {
  name: string
}

/** P25a: 上游 mcp-icons/ 46 连接器品牌(字母序,与 apps/app/assets/mcp-icons 一致) */
function CONNECTORS_LIST(): ConnectorItem[] {
  return [
    { name: 'Airtable' }, { name: 'Asana' }, { name: 'Box' }, { name: 'Brave Search' },
    { name: 'Cal.com' }, { name: 'Canva' }, { name: 'ClickUp' }, { name: 'Cloudflare' },
    { name: 'Confluence' }, { name: 'Discord' }, { name: 'Dropbox' }, { name: 'Exa' },
    { name: 'Figma' }, { name: 'GitHub' }, { name: 'GitLab' }, { name: 'Gmail' },
    { name: 'Google' }, { name: 'Google Calendar' }, { name: 'Google Docs' }, { name: 'Google Drive' },
    { name: 'Google Forms' }, { name: 'HubSpot' }, { name: 'Intercom' }, { name: 'Jira' },
    { name: 'Linear' }, { name: 'LinkedIn' }, { name: 'Memo' }, { name: 'Microsoft Teams' },
    { name: 'Mixpanel' }, { name: 'Monday' }, { name: 'Notion' }, { name: 'OneDrive' },
    { name: 'Outlook' }, { name: 'PostHog' }, { name: 'Postman' }, { name: 'Resend' },
    { name: 'Salesforce' }, { name: 'Shopify' }, { name: 'Slack' }, { name: 'Stripe' },
    { name: 'Supabase' }, { name: 'Vercel' }, { name: 'WhatsApp' }, { name: 'WordPress' },
    { name: 'YouTube' }, { name: 'Zendesk' }
  ]
}

/** P25a: 连接器稳定 hash 色(同品牌恒定;8 色板循环) */
function connectorColor(name: string): string {
  let h = 0
  for (let i = 0; i < name.length; i++) {
    h = (h * 31 + name.charCodeAt(i)) % 100000
  }
  const palette = ['#1A73E8', '#0F9D58', '#D93025', '#9334E6', '#E8710A', '#148F9C', '#C5221F', '#4285F4']
  return palette[h % palette.length]
}

/** P25a: 连接器显示首字母(取名称首个字母大写) */
function connectorInitial(name: string): string {
  if (name.length === 0) {
    return '?'
  }
  return name.substring(0, 1).toUpperCase()
}

@Extend(Text)
function monoText(): void {
  .fontFamily('monospace')
}

@Component
export struct NeoDashboardPanel {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @State agentStatuses: AgentStatusInfo[] = []
  @State connectedTools: string[] = []
  @State sessions: SessionRecord[] = []
  @State newAgentName: string = ''
  @State newAgentUrl: string = ''
  @State newAgentTask: string = ''
  @State showLlmSettings: boolean = false
  @State llmBaseUrlInput: string = ''
  @State llmApiKeyInput: string = ''
  @State llmModelInput: string = ''
  @State llmSaveHint: string = ''
  @State showMcpBoard: boolean = false
  @State connectHarness: string = ''
  @State connectJson: string = ''
  @State copiedHint: string = ''
  @State heroCopiedHint: string = ''
  @State sessionsRefreshTick: number = 0
  @State agentFormHint: string = ''
  // P34-E2: UltrafastBanner 状态（Preferences ultrafast_store: ultrafast_joined / ultrafast_dismissed）
  @State ultrafastHidden: boolean = false
  @State ultrafastToast: string = ''
  private ultraPrefs: preferences.Preferences | null = null
  private cockpitScroller: Scroller = new Scroller()
  shellBack: () => void = () => {}
  shellOpenReplay: (sessionId: string) => void = () => {}

  private readonly harnesses: HarnessDesc[] = [
    { name: 'Claude Code', desc: I18n.t('ndConnClaude'), logoBg: '#D97757', logoText: 'CC' },
    { name: 'Cursor', desc: I18n.t('ndConnCursor'), logoBg: '#2D2D30', logoText: 'Cu' },
    { name: 'VS Code', desc: I18n.t('ndConnVscode'), logoBg: '#22A06B', logoText: 'VS' },
    { name: 'Zed', desc: I18n.t('ndConnZed'), logoBg: '#2E6FE8', logoText: 'Z' },
    { name: 'Codex', desc: I18n.t('ndConnCodex'), logoBg: '#111111', logoText: 'Cx' }
  ]

  aboutToAppear(): void {
    this.agentStatuses = AgentEngine.getAllAgentStatus()
    this.connectedTools = ConnectionManager.getConnectedTools().map(t => t.displayName)
    const cfg = ConfigManager.get()
    this.llmBaseUrlInput = cfg.llmBaseUrl
    this.llmApiKeyInput = cfg.llmApiKey
    this.llmModelInput = cfg.llmModel
    this.sessions = SessionManager.getSessionList()
    EventBus.on(EventBusEvents.AGENT_STATUS_CHANGE, this.onAgentStatusChange)
    EventBus.on(EventBusEvents.AGENT_HEARTBEAT, this.onAgentStatusChange)
    // P34-E2: banner 持久化状态加载（joined/dismissed 任一 true 即永久隐藏）
    this.initUltrafastPrefs()
    console.info('NeoDashboardPanel mounted (P8 cockpit, sessions=' + this.sessions.length + ')')
  }

  /** P34-E2: ultrafast_store Preferences 初始化 + 已隐藏态读取 */
  private initUltrafastPrefs(): void {
    const ctx = this.getUIContext().getHostContext()
    if (!ctx) {
      console.error('[P34] ultrafast prefs init: no host context')
      return
    }
    preferences.getPreferences(ctx, 'ultrafast_store').then((p: preferences.Preferences) => {
      this.ultraPrefs = p
      const joined = p.getSync('ultrafast_joined', false) as boolean
      const dismissed = p.getSync('ultrafast_dismissed', false) as boolean
      this.ultrafastHidden = joined || dismissed
      console.info('[P34] ultrafast banner state: joined=' + joined + ' dismissed=' + dismissed + ' hidden=' + this.ultrafastHidden)
    }).catch((e: Object) => {
      console.error('[P34] ultrafast prefs init fail: ' + e)
    })
  }

  /** P34-E2: Request early access → joined=true + toast + 永久隐藏 */
  private joinUltrafast(): void {
    console.info('[P34] ultrafast join clicked')
    this.ultrafastHidden = true
    this.ultrafastToast = I18n.t('ntJoinWaitlist')
    setTimeout(() => { this.ultrafastToast = '' }, 2000)
    const p = this.ultraPrefs
    if (p !== null) {
      p.put('ultrafast_joined', true).then(() => { p.flush() }).catch((e: Object) => {
        console.error('[P34] ultrafast join persist fail: ' + e)
      })
    }
  }

  /** P34-E2: X 关闭 → dismissed=true + 永久隐藏 */
  private dismissUltrafast(): void {
    console.info('[P34] ultrafast banner dismissed')
    this.ultrafastHidden = true
    const p = this.ultraPrefs
    if (p !== null) {
      p.put('ultrafast_dismissed', true).then(() => { p.flush() }).catch((e: Object) => {
        console.error('[P34] ultrafast dismiss persist fail: ' + e)
      })
    }
  }

  aboutToDisappear(): void {
    EventBus.off(EventBusEvents.AGENT_STATUS_CHANGE, this.onAgentStatusChange)
    EventBus.off(EventBusEvents.AGENT_HEARTBEAT, this.onAgentStatusChange)
  }

  private onAgentStatusChange = (data: Object): void => {
    this.agentStatuses = AgentEngine.getAllAgentStatus()
    this.sessions = SessionManager.getSessionList()
  }

  private maskKey(key: string): string {
    if (key.length <= 4) {
      return '****'
    }
    return key.substring(0, 2) + '****' + key.substring(key.length - 2)
  }

  private getAgentUrl(agentId: string): string {
    const config = AgentEngine.getAgentConfig(agentId)
    if (!config) {
      return ''
    }
    const tab = TabManager.getTab(config.tabId)
    const status = AgentEngine.getAgentStatus(agentId)
    if (status && status.currentUrl) {
      return status.currentUrl
    }
    if (tab && tab.currentUrl) {
      return tab.currentUrl
    }
    return config.targetUrl
  }

  private getMcpEndpoint(): string {
    const port = MCPServer.isRunning() ? MCPServer.getPort() : ConfigManager.getMcpPort()
    const token = MCPServer.getAuthToken()
    return `http://<本机IP>:${port}/mcp?token=${token.length > 0 ? token : '<token>'}`
  }

  private buildHarnessJson(name: string): string {
    const port = MCPServer.isRunning() ? MCPServer.getPort() : ConfigManager.getMcpPort()
    const token = MCPServer.getAuthToken()
    const cfg: Record<string, Object> = {
      'mcpServers': {
        'browseros': {
          'url': `http://127.0.0.1:${port}/mcp?token=${token.length > 0 ? token : '<token>'}`,
          'harness': name
        } as Record<string, Object>
      } as Record<string, Object>
    }
    return JSON.stringify(cfg, null, 2)
  }

  private copyToClipboard(text: string, which: number): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      pasteboard.getSystemPasteboard().setData(data)
      if (which === 0) {
        this.heroCopiedHint = I18n.t('copied')
        setTimeout(() => { this.heroCopiedHint = '' }, 1500)
      } else {
        this.copiedHint = I18n.t('copied')
        setTimeout(() => { this.copiedHint = '' }, 1500)
      }
      console.info('NeoDashboardPanel copied to clipboard len=' + text.length)
    } catch (e) {
      console.error('NeoDashboardPanel clipboard error: ' + e)
    }
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('NeoDashboardPanel theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Column() {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }
        // P51-C: localeVersion anchor
        if (this.localeVersion < 0) {
          Text('').fontSize(0)
        }

      if (this.showMcpBoard) {
        this.McpBoard()
      } else {
        this.Cockpit()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surfaceAlt)
  }

  // ---------- C1: Cockpit 新标签页 ----------

  @Builder
  Cockpit(): void {
    Column() {
      Row() {
        Text('BrowserOS neo')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .layoutWeight(1)

        // P45-D: 搜索引擎常驻指示条 —— 建议下拉里的「切换」入口太深（须先点地址栏），
        // 用户找不到搜索引擎设置。Cockpit 头部常驻显示当前引擎，点击直达设置搜索节。
        Row() {
          Image($rawfile('ic_search.svg'))
            .width(12).height(12)
            .fillColor(this.pal().text2)
            .draggable(false)
          Text(I18n.t('ntSearchEngine') + getEngineById(ConfigManager.getSearchEngineId()).name)
            .fontSize(11)
            .fontColor(this.pal().text2)
            .maxLines(1)
            .constraintSize({ maxWidth: 140 })
            .margin({ left: 5 })
          Text(I18n.t('ntSwitch'))
            .fontSize(11)
            .fontColor('#1A73E8')
            .margin({ left: 6 })
        }
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(15)
        .margin({ left: 8 })
        .onClick(() => {
          console.info('[P45] dashboard engine switch entry clicked')
          const navParams: Record<string, Object> = { 'section': 'search' }
          router.pushUrl({ url: 'pages/SettingsPage', params: navParams })
        })

        Button(I18n.t('ndMcpBoard'))
          .fontSize(12)
          .height(30)
          .backgroundColor('#2D2D30')
          .fontColor('#FFFFFF')
          .borderRadius(15)
          .onClick(() => {
            console.info('NeoDashboardPanel open MCP board')
            this.showMcpBoard = true
          })

        Row() {
          Image($rawfile('ic_close.svg'))
            .width(14).height(14)
            .fillColor(this.pal().text)
            .draggable(false)
          Text(I18n.t('close'))
            .fontSize(12)
            .fontColor(this.pal().text)
            .margin({ left: 4 })
        }
        .height(30)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(15)
        .margin({ left: 8 })
        .onClick(() => {
          console.info('NeoDashboardPanel close panel')
          this.shellBack()
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Scroll() {
        Column() {
          this.TileGrid()
          this.UltrafastBanner()
          this.RecentSessionsCard()
          this.AgentSetupCard()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  /** 3 列磁贴网格：首行第一块 2x 宽 hero 渐变卡 */
  @Builder
  TileGrid(): void {
    GridRow({ columns: 3, gutter: { x: 10, y: 10 } }) {
      GridCol({ span: 2 }) {
        this.HeroCard()
      }
      GridCol() {
        this.SkillsTile()
      }
      if (this.agentStatuses.length === 0) {
        GridCol() {
          this.EmptyStateTile()
        }
      } else {
        ForEach(this.agentStatuses, (status: AgentStatusInfo) => {
          GridCol() {
            this.AgentTile(status)
          }
        }, (status: AgentStatusInfo) => status.agentId + '_' + status.status + '_' + status.progress)
      }
    }
    .width('100%')
    .margin({ top: 8 })
  }

  /** hero 渐变卡（2x 宽）：P34-E1 上游 CockpitHero 三段式 1:1 + 快速入口 */
  @Builder
  HeroCard(): void {
    Column() {
      // P34-E1: 产品名降级为左上小角标（12fp 半透明），原中文副标题删除（1:1）
      Text('BrowserOS neo')
        .fontSize(12)
        .fontColor('#FFFFFFB3')
        .margin({ top: 10 })
        .alignSelf(ItemAlign.Start)

      Blank()

      // P34-E1: 上游原文三段式 lead + working on(粗斜体蓝) + tail，extrabold 26fp 字距收紧
      Text() {
        Span('What are your agents ')
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .fontSize(26)
        Span('working on')
          .fontColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
          .fontWeight(FontWeight.Bold)
          .fontStyle(FontStyle.Italic)
          .fontSize(26)
        Span(' right now?')
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .fontSize(26)
      }
      .lineHeight(32)
      .letterSpacing(-0.3)
      .maxLines(2)
      .alignSelf(ItemAlign.Start)

      Row() {
        Button(I18n.t('ntViewAgent'))
          .fontSize(11)
          .height(28)
          .backgroundColor(this.pal().surface)
          .fontColor('#2E6FE8')
          .borderRadius(14)
          .onClick(() => {
            // P8d: 滚动到创建代理表单（表单常驻在 RecentSessionsCard 之后）
            this.showLlmSettings = true
            this.cockpitScroller.scrollEdge(Edge.Bottom)
            console.info('NeoDashboardPanel hero: scroll to agent setup card')
          })
        Text(' · ')
          .fontSize(11)
          .fontColor('#FFFFFFCC')
        Text(`${this.agentStatuses.length}${I18n.t('ndAgents')}${this.sessions.length}${I18n.t('ndSessions')}`)
          .fontSize(10)
          .fontColor('#FFFFFFCC')
      }
      .margin({ top: 8, bottom: 12 })
    }
    .width('100%')
    .height(150)
    .padding({ left: 14, right: 14 })
    .borderRadius(14)
    .linearGradient({
      angle: 135,
      colors: [['#2E6FE8', 0], ['#8B5CF6', 1]]
    })
    .alignItems(HorizontalAlign.Start)
  }

  /** P34-F: Skills 入口磁贴（驾驶舱网格第一行右侧）→ pages/SkillsPage */
  @Builder
  SkillsTile(): void {
    Column() {
      Image($rawfile('ic_robot.svg'))
        .width(22).height(22)
        .fillColor('#2E6FE8')
        .draggable(false)
      Text('Skills')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().text)
        .margin({ top: 8 })
      Text(I18n.t('ndSkills'))
        .fontSize(10)
        .fontColor(this.pal().text2)
        .margin({ top: 2 })
    }
    .width('100%')
    .height(150)
    .borderRadius(14)
    .backgroundColor(this.pal().surfaceInput)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      console.info('[P34] skills tile clicked -> pages/SkillsPage')
      router.pushUrl({ url: 'pages/SkillsPage' })
    })
  }

  /** P34-E2: UltrafastBanner —— hero 网格正下方（对标 up_ultra.tsx 布局语义） */
  @Builder
  UltrafastBanner(): void {
    if (!this.ultrafastHidden) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Row() {
          Image($rawfile('ic_zap.svg'))
            .width(16).height(16)
            .fillColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
            .draggable(false)
          Text() {
            Span('Ultrafast')
              .fontColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
              .fontWeight(FontWeight.Bold)
              .fontStyle(FontStyle.Italic)
            Span(' mode')
              .fontColor(this.pal().text)
              .fontWeight(FontWeight.Bold)
          }
          .fontSize(15)
          .margin({ left: 8 })

          Text('Faster browser tasks. 10× fewer tokens from your main agent.')
            .fontSize(12)
            .fontColor(this.pal().text2)
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 14 })
            .padding({ left: 14 })
            .border({ width: { left: 1 }, color: this.pal().border })

          Text('Request early access →')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.darkMode ? '#7CB1FF' : '#1A73E8')
            .margin({ left: 14 })
            .onClick(() => {
              this.joinUltrafast()
            })
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .padding({ left: 18, right: 44, top: 10, bottom: 10 })
        .alignItems(VerticalAlign.Center)

        // X 关闭钮（右上角）
        Button({ type: ButtonType.Normal }) {
          Image($rawfile('ic_close.svg'))
            .width(14).height(14)
            .fillColor(this.pal().text)
            .draggable(false)
        }
        .width(28)
        .height(28)
        .backgroundColor(Color.Transparent)
        .margin({ top: 6, right: 6 })
        .accessibilityText(I18n.t('ntCloseBanner'))
        .onClick(() => {
          this.dismissUltrafast()
        })
      }
      .width('100%')
      .borderRadius(10)
      .backgroundColor(this.darkMode ? '#39445766' : '#E8F0FE99')
      .border({ width: 1, color: this.pal().border })
      .margin({ top: 10 })
    }
    // P34-E2: join toast（底部居中）
    if (this.ultrafastToast.length > 0) {
      Text(this.ultrafastToast)
        .fontSize(12)
        .fontColor('#FFFFFF')
        .backgroundColor('#CC1F1F22')
        .borderRadius(16)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .position({ x: '50%', y: '88%' })
        .translate({ x: -60 })
    }
  }

  /** 空态磁贴（无代理时占位一块） */
  @Builder
  EmptyStateTile(): void {
    Column() {
      Text(I18n.t('ndNoAgent'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().text2)
      Text(I18n.t('ndNoAgentDesc'))
        .fontSize(10)
        .fontColor(this.pal().text2)
        .margin({ top: 4 })
    }
    .width('100%')
    .height(150)
    .borderRadius(14)
    .backgroundColor(this.pal().surfaceInput)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** agent 磁贴：缩略区 + 状态点 + 标签名 + URL + agent 名 + 进度条 */
  @Builder
  AgentTile(status: AgentStatusInfo): void {
    Column() {
      // 页面内容缩略区
      Column() {
        Blank()
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.pal().surface)
      .borderRadius({ topLeft: 12, topRight: 12 })

      // 底部信息条
      Column() {
        Row() {
          Circle({ width: 7, height: 7 })
            .fill(this.getStatusColor(status.status))
            .margin({ right: 5 })
          Text(status.agentId.length > 12 ? status.agentId.substring(0, 12) : status.agentId)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal().text)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (status.status === AgentStatus.RUNNING) {
            Text(I18n.t('asStop'))
              .fontSize(9)
              .fontColor('#C43E3E')
              .onClick(() => {
                AgentEngine.terminateAgent(status.agentId)
              })
          }
        }
        .width('100%')

        Text(this.getAgentUrl(status.agentId) || 'about:blank')
          .fontSize(9)
          .fontColor(this.pal().text2)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })

        // 进度条
        Row() {
          Row() {
            Blank()
          }
          .width(status.progress > 100 ? '100%' : `${status.progress}%`)
          .height(3)
          .backgroundColor(this.getStatusColor(status.status))
          .borderRadius(2)
          Blank()
        }
        .width('100%')
        .height(3)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(2)
        .margin({ top: 5, bottom: 5 })

        if (status.status === AgentStatus.COMPLETED || status.status === AgentStatus.ERROR) {
          Text(I18n.t('hiReplay'))
            .fontSize(10)
            .fontColor('#2E6FE8')
            .onClick(() => {
              const sid = AgentEngine.getSessionId(status.agentId)
              if (sid.length > 0) {
                console.info('NeoDashboardPanel replay sessionId=' + sid)
                this.shellOpenReplay(sid)
              } else {
                console.warn('NeoDashboardPanel replay: no session for agent=' + status.agentId)
              }
            })
        }
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 8 })
    }
    .width('100%')
    .height(150)
    .borderRadius(12)
    .backgroundColor(this.pal().surfaceInput)
    .clip(true)
    .onClick(() => {
      // 点击磁贴切到该 agent 的 tab
      const config = AgentEngine.getAgentConfig(status.agentId)
      if (config) {
        TabManager.switchTab(config.tabId)
        this.shellBack()
      }
    })
  }

  /** 深色页脚卡：最近会话列表 */
  @Builder
  RecentSessionsCard(): void {
    Column() {
      Row() {
        Text(I18n.t('ndRecent'))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
        Text(`${this.sessions.length}` + I18n.t('ntCountEnd'))
          .fontSize(10)
          .fontColor('#9AA0A6')
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.sessions.length === 0) {
        Text(I18n.t('ndNoSession'))
          .fontSize(11)
          .fontColor('#9AA0A6')
          .margin({ top: 8, bottom: 8 })
      } else {
        ForEach(this.sessions.slice(0, 5), (s: SessionRecord) => {
          Row() {
            Circle({ width: 6, height: 6 })
              .fill(s.endTime > 0 ? '#22A06B' : '#C43E3E')
              .margin({ right: 8 })
            Text(s.agentId.length > 14 ? s.agentId.substring(0, 14) : s.agentId)
              .fontSize(11)
              .fontColor('#E8EAED')
              .layoutWeight(1)
            Text(`${s.operationLogs.length}` + I18n.t('asSteps'))
              .fontSize(10)
              .fontColor('#9AA0A6')
              .margin({ right: 8 })
            Text(I18n.t('hiReplay'))
              .fontSize(10)
              .fontColor('#8AB4F8')
              .onClick(() => {
                console.info('NeoDashboardPanel footer replay sessionId=' + s.sessionId)
                this.shellOpenReplay(s.sessionId)
              })
          }
          .width('100%')
          .padding({ top: 6, bottom: 6 })
        }, (s: SessionRecord) => s.sessionId)
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor('#2D2D30')
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  // ---------- P8c: LLM 设置 + 创建代理（常驻表单，自 NeoDashboardPage 移植） ----------

  /** 白卡表单：LLM 接入设置 + 创建并启动代理（handler 照搬 NeoDashboardPage 已验收路径） */
  @Builder
  AgentSetupCard(): void {
    Column() {
      Text(I18n.t('stLlmCard'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .alignSelf(ItemAlign.Start)

      Text(I18n.t('stApiEndpoint'))
        .fontSize(11)
        .fontColor(this.pal().text2)
        .margin({ top: 10, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmBaseUrlInput, placeholder: 'https://api.example.com/v1' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(36)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(8)
        .onChange((value: string) => { this.llmBaseUrlInput = value })

      Text('API Key')
        .fontSize(11)
        .fontColor(this.pal().text2)
        .margin({ top: 8, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmApiKeyInput, placeholder: I18n.t('stApiKeyPh') }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(36)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(8)
        .onChange((value: string) => { this.llmApiKeyInput = value })

      Text(I18n.t('stModelName'))
        .fontSize(11)
        .fontColor(this.pal().text2)
        .margin({ top: 8, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmModelInput, placeholder: I18n.t('stModelPh') }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(36)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(8)
        .onChange((value: string) => { this.llmModelInput = value })

      Row() {
        Button(I18n.t('saveConfig'))
          .fontSize(12)
          .height(32)
          .backgroundColor('#2E6FE8')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(async () => {
            const ok = await ConfigManager.update({
              llmBaseUrl: this.llmBaseUrlInput,
              llmApiKey: this.llmApiKeyInput,
              llmModel: this.llmModelInput
            } as AppConfigUpdate)
            this.llmSaveHint = ok ? I18n.t('saved') : I18n.t('saveFailedCfg')
            console.info('NeoDashboardPanel llm config saved: ' + this.llmSaveHint)
          })
        if (this.llmSaveHint.length > 0) {
          Text(this.llmSaveHint)
            .fontSize(11)
            .fontColor(this.llmSaveHint === I18n.t('saved') ? '#22A06B' : '#C43E3E')
            .margin({ left: 10 })
        }
      }
      .width('100%')
      .margin({ top: 12 })

      Divider()
        .color(this.pal().border)
        .margin({ top: 14, bottom: 12 })

      Text(I18n.t('ndCreateAgent'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .alignSelf(ItemAlign.Start)

      Text(I18n.t('ndAgentName'))
        .fontSize(11)
        .fontColor(this.pal().text2)
        .margin({ top: 10, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.newAgentName, placeholder: I18n.t('ndAgentNamePh') }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(36)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(8)
        .onChange((value: string) => { this.newAgentName = value })

      Text(I18n.t('ndTargetUrl'))
        .fontSize(11)
        .fontColor(this.pal().text2)
        .margin({ top: 8, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.newAgentUrl, placeholder: 'https://example.com' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(36)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(8)
        .onChange((value: string) => { this.newAgentUrl = value })

      Text(I18n.t('ndTaskDesc'))
        .fontSize(11)
        .fontColor(this.pal().text2)
        .margin({ top: 8, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.newAgentTask, placeholder: '如 open the page and tell me the page title' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(36)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(8)
        .onChange((value: string) => { this.newAgentTask = value })

      Button(I18n.t('ndCreateBtn'))
        .fontSize(13)
        .width('100%')
        .height(38)
        .backgroundColor('#22A06B')
        .fontColor('#FFFFFF')
        .borderRadius(8)
        .margin({ top: 12 })
        .onClick(() => {
          if (this.newAgentName.length > 0 && this.newAgentUrl.length > 0) {
            AgentEngine.createAgent(
              this.newAgentName,
              this.newAgentUrl,
              this.newAgentTask,
              RunStrategy.ONCE
            )
            this.agentFormHint = I18n.t('ndAgentCreated')
            this.newAgentName = ''
            this.newAgentUrl = ''
            this.newAgentTask = ''
            this.agentStatuses = AgentEngine.getAllAgentStatus()
            console.info('NeoDashboardPanel agent created (P8c form)')
          } else {
            this.agentFormHint = I18n.t('ndAgentFormErr')
          }
        })

      if (this.agentFormHint.length > 0) {
        Text(this.agentFormHint)
          .fontSize(11)
          .fontColor('#2E6FE8')
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(this.pal().surface)
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  // ---------- P25a: 连接器目录(46 家品牌) ----------

  /** 连接器点击 toast 文案('' = 隐藏) */
  @State connectorToast: string = ''

  /** P25a: 连接器卡片(首字母彩色圆徽 + 名称;点击复制连接器名) */
  @Builder
  ConnectorCatalog(): void {
    Column() {
      Text(I18n.t('ndConnectorDir') + `${CONNECTORS_LIST().length})`)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
      Text(I18n.t('ndConnectorHint'))
        .fontSize(10)
        .fontColor(this.pal().text2)
        .margin({ top: 2 })

      GridRow({ columns: 4, gutter: { x: 8, y: 8 } }) {
        ForEach(CONNECTORS_LIST(), (c: ConnectorItem) => {
          GridCol() {
            Column() {
              Text(connectorInitial(c.name))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .width(34)
                .height(34)
                .textAlign(TextAlign.Center)
                .borderRadius(17)
                .backgroundColor(connectorColor(c.name))
              Text(c.name)
                .fontSize(9)
                .fontColor(this.pal().text)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 5 })
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .borderRadius(10)
            .backgroundColor(this.pal().surface)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.copyConnectorName(c.name)
            })
          }
        }, (c: ConnectorItem) => c.name)
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(this.pal().surfaceInput)
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  /** P25a: 复制连接器名 + toast 反馈 */
  private copyConnectorName(name: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, name)
      pasteboard.getSystemPasteboard().setData(data)
    } catch (e) {
      console.error('ConnectorCatalog copy error: ' + e)
    }
    this.connectorToast = name + I18n.t('ndComingSoon')
    setTimeout(() => {
      this.connectorToast = ''
    }, 1500)
    console.info('ConnectorCatalog click: ' + name)
  }

  // ---------- C2: MCP Install Board ----------

  @Builder
  McpBoard(): void {
    // P8c 修复记录：原实现把 Connect 弹层挂在占满 100% 高度的内容 Column 之后，
    // 被挤出屏幕可视区 —— Connect 点击"无任何可见反馈"的真根因。
    // 现结构：Stack(100%×100%) 三层 —— 内容层 / 半透明遮罩 / 居中弹层（后声明者在上）。
    Stack() {
      Column() {
        Row() {
          Row() {
            Image($rawfile('ic_back.svg'))
              .width(14).height(14)
              .fillColor(this.pal().text)
              .draggable(false)
            Text(I18n.t('ndBackCockpit'))
              .fontSize(12)
              .fontColor(this.pal().text)
              .margin({ left: 4 })
          }
          .height(30)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.pal().surfaceInput)
          .borderRadius(15)
          .onClick(() => {
            this.showMcpBoard = false
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: 16, top: 10 })

        Scroll() {
          Column() {
            // 深灰 hero 卡：本地 MCP 端点
            Column() {
              Text(I18n.t('ndMcpEndpoint'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
              Text(I18n.t('ndMcpDesc'))
                .fontSize(11)
                .fontColor('#BDC1C6')
                .margin({ top: 4 })

              Row() {
                Text(this.getMcpEndpoint())
                  .fontSize(11)
                  .fontFamily('monospace')
                  .fontColor('#8AB4F8')
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .backgroundColor('#1F1F22')
                  .borderRadius(6)
                  .padding({ left: 8, right: 8, top: 6, bottom: 6 })

                Button(this.heroCopiedHint.length > 0 ? this.heroCopiedHint : 'Copy')
                  .fontSize(11)
                  .height(30)
                  .backgroundColor('#2E6FE8')
                  .fontColor('#FFFFFF')
                  .borderRadius(6)
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.copyToClipboard(this.getMcpEndpoint(), 0)
                  })

                Button('Docs')
                  .fontSize(11)
                  .height(30)
                  .backgroundColor('#3C4043')
                  .fontColor('#FFFFFF')
                  .borderRadius(6)
                  .margin({ left: 6 })
                  .onClick(() => {
                    console.info('McpBoard Docs clicked')
                  })
              }
              .width('100%')
              .margin({ top: 12 })
            }
            .width('100%')
            .padding(16)
            .borderRadius(14)
            .backgroundColor('#333333')
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 8 })

            // harness 网格
            GridRow({ columns: 2, gutter: { x: 10, y: 10 } }) {
              ForEach(this.harnesses, (h: HarnessDesc) => {
                GridCol() {
                  Column() {
                    Row() {
                      // 方形 logo 位
                      Text(h.logoText)
                        .fontSize(14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#FFFFFF')
                        .width(36)
                        .height(36)
                        .textAlign(TextAlign.Center)
                        .borderRadius(8)
                        .backgroundColor(h.logoBg)

                      Text(h.name)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.pal().text)
                        .margin({ left: 10 })
                        .layoutWeight(1)
                    }
                    .width('100%')

                    Text(h.desc)
                      .fontSize(10)
                      .fontColor(this.pal().text2)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 6 })

                    Button('Connect')
                      .fontSize(11)
                      .height(28)
                      .backgroundColor('#1A73E8')
                      .fontColor('#FFFFFF')
                      .borderRadius(14)
                      .margin({ top: 8 })
                      .alignSelf(ItemAlign.End)
                      .onClick(() => {
                        this.connectHarness = h.name
                        this.connectJson = this.buildHarnessJson(h.name)
                        this.copyToClipboard(this.connectJson, 1)
                        console.info('McpBoard connect harness=' + h.name + ' (config copied)')
                      })
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(12)
                  .backgroundColor(this.pal().surface)
                  .alignItems(HorizontalAlign.Start)
                }
              }, (h: HarnessDesc) => h.name)
            }
            .width('100%')
            .margin({ top: 12 })

            // P25a: 连接器目录区块(46 家品牌)
            this.ConnectorCatalog()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')

      // 半透明遮罩（弹层打开时）
      if (this.connectHarness.length > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
      }

      // Connect 弹层：居中显示 harness JSON 配置 + 复制反馈
      if (this.connectHarness.length > 0) {
        Column() {
          Text(`${this.connectHarness}` + I18n.t('ndMcpCfg'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')

          Scroll() {
            Text(this.connectJson)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor('#8AB4F8')
              .backgroundColor('#1F1F22')
              .borderRadius(8)
              .padding(10)
          }
          .constraintSize({ maxHeight: 180 })
          .margin({ top: 10 })

          Row() {
            Button(this.copiedHint.length > 0 ? this.copiedHint : I18n.t('ndCopyJson'))
              .fontSize(12)
              .height(32)
              .backgroundColor('#2E6FE8')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                this.copyToClipboard(this.connectJson, 1)
              })

            Button(I18n.t('close'))
              .fontSize(12)
              .height(32)
              .backgroundColor('#3C4043')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .margin({ left: 10 })
              .onClick(() => {
                this.connectHarness = ''
              })
          }
          .margin({ top: 12 })
        }
        .width('86%')
        .padding(16)
        .borderRadius(14)
        .backgroundColor('#2D2D30')
      }

      // P25a: 连接器 toast 浮层(底部居中)
      if (this.connectorToast.length > 0) {
        Text(this.connectorToast)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor('#CC1F1F22')
          .borderRadius(16)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .position({ x: '50%', y: '88%' })
          .translate({ x: -60 })
      }
    }
    .width('100%')
    .height('100%')
  }

  private getStatusText(status: AgentStatus): string {
    switch (status) {
      case AgentStatus.IDLE:
        return I18n.t('ndIdle')
      case AgentStatus.RUNNING:
        return I18n.t('ndRunning')
      case AgentStatus.COMPLETED:
        return I18n.t('ndCompleted')
      case AgentStatus.ERROR:
        return I18n.t('ndError')
      case AgentStatus.STOPPED:
        return I18n.t('ndStopped')
      case AgentStatus.PAUSED:
        return I18n.t('ndPaused')
      default:
        return status
    }
  }

  private getStatusColor(status: AgentStatus): string {
    switch (status) {
      case AgentStatus.RUNNING:
        return '#C43E3E'
      case AgentStatus.COMPLETED:
        return '#22A06B'
      case AgentStatus.IDLE:
      case AgentStatus.PAUSED:
        return '#2E6FE8'
      case AgentStatus.ERROR:
      case AgentStatus.STOPPED:
        return '#C43E3E'
      default:
        return '#999999'
    }
  }
}
