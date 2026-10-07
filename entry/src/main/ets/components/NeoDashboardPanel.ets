import { AgentEngine } from '../service/AgentEngine'
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
import { Palette } from '../common/Palette'
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

@Extend(Text)
function monoText(): void {
  .fontFamily('monospace')
}

@Component
export struct NeoDashboardPanel {
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') darkMode: boolean = false

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
  private cockpitScroller: Scroller = new Scroller()
  shellBack: () => void = () => {}
  shellOpenReplay: (sessionId: string) => void = () => {}

  private readonly harnesses: HarnessDesc[] = [
    { name: 'Claude Code', desc: 'Anthropic 终端代理，一键接入浏览器', logoBg: '#D97757', logoText: 'CC' },
    { name: 'Cursor', desc: 'AI 代码编辑器，MCP 直连', logoBg: '#2D2D30', logoText: 'Cu' },
    { name: 'VS Code', desc: '微软编辑器，Copilot 好搭档', logoBg: '#22A06B', logoText: 'VS' },
    { name: 'Zed', desc: '高性能编辑器，轻量接入', logoBg: '#2E6FE8', logoText: 'Z' },
    { name: 'Codex', desc: 'OpenAI 编码代理，同一键安装', logoBg: '#111111', logoText: 'Cx' }
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
    console.info('NeoDashboardPanel mounted (P8 cockpit, sessions=' + this.sessions.length + ')')
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
        this.heroCopiedHint = '已复制'
        setTimeout(() => { this.heroCopiedHint = '' }, 1500)
      } else {
        this.copiedHint = '已复制'
        setTimeout(() => { this.copiedHint = '' }, 1500)
      }
      console.info('NeoDashboardPanel copied to clipboard len=' + text.length)
    } catch (e) {
      console.error('NeoDashboardPanel clipboard error: ' + e)
    }
  }

  build(): void {
    Column() {
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

        Button('MCP 安装板')
          .fontSize(12)
          .height(30)
          .backgroundColor('#2D2D30')
          .fontColor('#FFFFFF')
          .borderRadius(15)
          .onClick(() => {
            console.info('NeoDashboardPanel open MCP board')
            this.showMcpBoard = true
          })

        Button('关闭 ×')
          .fontSize(12)
          .height(30)
          .backgroundColor(this.pal().surfaceInput)
          .fontColor(this.pal().text)
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

  /** hero 渐变卡（2x 宽）：产品名 + 副标题 + 快速入口 */
  @Builder
  HeroCard(): void {
    Column() {
      Text('BrowserOS neo')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .margin({ top: 14 })

      Text('给 AI 代理用的浏览器 —— 实时驾驶舱')
        .fontSize(11)
        .fontColor('#E8EAF6')
        .margin({ top: 6 })

      Blank()

      Row() {
        Button('查看代理')
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
        Text(`${this.agentStatuses.length} 个代理 · ${this.sessions.length} 个会话`)
          .fontSize(10)
          .fontColor('#FFFFFFCC')
      }
      .margin({ bottom: 12 })
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

  /** 空态磁贴（无代理时占位一块） */
  @Builder
  EmptyStateTile(): void {
    Column() {
      Text('暂无代理')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().text2)
      Text('在下方创建第一个 AI 代理')
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
            Text('停止')
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
          Text('▶ 回放')
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
        Text('最近会话')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
        Text(`${this.sessions.length} 条`)
          .fontSize(10)
          .fontColor('#9AA0A6')
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.sessions.length === 0) {
        Text('暂无会话 —— 跑一个代理任务后自动录制')
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
            Text(`${s.operationLogs.length} 步`)
              .fontSize(10)
              .fontColor('#9AA0A6')
              .margin({ right: 8 })
            Text('回放 ▶')
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
      Text('LLM 接入（OpenAI 兼容）')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .alignSelf(ItemAlign.Start)

      Text('API 端点')
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
      TextInput({ text: this.llmApiKeyInput, placeholder: 'sk-...（本地服务可留空）' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(36)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(8)
        .onChange((value: string) => { this.llmApiKeyInput = value })

      Text('模型名')
        .fontSize(11)
        .fontColor(this.pal().text2)
        .margin({ top: 8, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.llmModelInput, placeholder: '如 agnes-3.0-flash' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(36)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(8)
        .onChange((value: string) => { this.llmModelInput = value })

      Row() {
        Button('保存配置')
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
            this.llmSaveHint = ok ? '已保存' : '保存失败：配置校验未通过'
            console.info('NeoDashboardPanel llm config saved: ' + this.llmSaveHint)
          })
        if (this.llmSaveHint.length > 0) {
          Text(this.llmSaveHint)
            .fontSize(11)
            .fontColor(this.llmSaveHint === '已保存' ? '#22A06B' : '#C43E3E')
            .margin({ left: 10 })
        }
      }
      .width('100%')
      .margin({ top: 12 })

      Divider()
        .color(this.pal().border)
        .margin({ top: 14, bottom: 12 })

      Text('创建并启动代理')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().text)
        .alignSelf(ItemAlign.Start)

      Text('代理名称')
        .fontSize(11)
        .fontColor(this.pal().text2)
        .margin({ top: 10, bottom: 4 })
        .alignSelf(ItemAlign.Start)
      TextInput({ text: this.newAgentName, placeholder: '如 p8c-e2e' }).fontColor(this.pal().text).placeholderColor(this.pal().text2)
        .width('100%')
        .height(36)
        .backgroundColor(this.pal().surfaceInput)
        .borderRadius(8)
        .onChange((value: string) => { this.newAgentName = value })

      Text('目标 URL')
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

      Text('任务描述')
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

      Button('创建代理')
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
            this.agentFormHint = '代理已创建并启动，见上方磁贴'
            this.newAgentName = ''
            this.newAgentUrl = ''
            this.newAgentTask = ''
            this.agentStatuses = AgentEngine.getAllAgentStatus()
            console.info('NeoDashboardPanel agent created (P8c form)')
          } else {
            this.agentFormHint = '请填写代理名称和目标 URL'
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

  // ---------- C2: MCP Install Board ----------

  @Builder
  McpBoard(): void {
    // P8c 修复记录：原实现把 Connect 弹层挂在占满 100% 高度的内容 Column 之后，
    // 被挤出屏幕可视区 —— Connect 点击"无任何可见反馈"的真根因。
    // 现结构：Stack(100%×100%) 三层 —— 内容层 / 半透明遮罩 / 居中弹层（后声明者在上）。
    Stack() {
      Column() {
        Row() {
          Button('← 返回驾驶舱')
            .fontSize(12)
            .height(30)
            .backgroundColor(this.pal().surfaceInput)
            .fontColor(this.pal().text)
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
              Text('本地 MCP 端点')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
              Text('把 AI 工具接到 BrowserOS —— MCP 标准协议')
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
          Text(`${this.connectHarness} — MCP 配置`)
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
            Button(this.copiedHint.length > 0 ? this.copiedHint : '复制 JSON')
              .fontSize(12)
              .height(32)
              .backgroundColor('#2E6FE8')
              .fontColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => {
                this.copyToClipboard(this.connectJson, 1)
              })

            Button('关闭')
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
    }
    .width('100%')
    .height('100%')
  }

  private getStatusText(status: AgentStatus): string {
    switch (status) {
      case AgentStatus.IDLE:
        return '空闲'
      case AgentStatus.RUNNING:
        return '运行中'
      case AgentStatus.COMPLETED:
        return '已完成'
      case AgentStatus.ERROR:
        return '错误'
      case AgentStatus.STOPPED:
        return '已停止'
      case AgentStatus.PAUSED:
        return '已暂停'
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
