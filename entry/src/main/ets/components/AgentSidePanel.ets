/**
 * P9-B: Agent 侧边面板（ref1 一比一复刻）
 * 右侧 360vp 常驻面板：顶部标题栏（Agent + 模型下拉 + ⚙）+ 消息气泡列表
 * + 底部多行输入 + 发送。发送 = AgentEngine.createAgent（与 Dashboard 磁贴联动）。
 */
import { AgentEngine } from '../service/AgentEngine'
import { SessionManager } from '../service/SessionManager'
import { SessionRecord } from '../model/SessionRecord'
import { ConfigManager } from '../storage/ConfigManager'
import { RunStrategy, AgentStatus } from '../common/Types'
import { AgentStatusInfo } from '../model/AgentStatus'
import { Palette } from '../common/Palette'
import { router } from '@kit.ArkUI'

interface ChatMessage {
  role: string // 'user' | 'agent' | 'hint'
  text: string
  agentId: string
}

@Component
export struct AgentSidePanel {
  /** p10a: AppStorage('darkMode') 消费 —— EntryAbility 启动时与设置页开关写入 */
  @StorageProp('darkMode') darkMode: boolean = false

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  @State messages: ChatMessage[] = []
  @State inputText: string = ''
  @State modelSelection: number = 0
  @State agents: AgentStatusInfo[] = []
  @State showModelDropdown: boolean = false
  /** P21b: 面板双视图——chat(默认,上游 index 路由) / history(上游 /history 路由) */
  @State panelView: string = 'chat'
  /** P21b: history 视图数据(时间倒序,getSessionListAsync) */
  @State historySessions: SessionRecord[] = []
  /** P21b: history 加载态(防止闪空态) */
  @State historyLoading: boolean = false
  onClose: () => void = () => {}
  /** P19a: 已回流过终态的 agent（去重，避免轮询重复推气泡） */
  private settledAgents: Set<string> = new Set()
  /** P19a: 终态轮询句柄（aboutToDisappear 必清） */
  private pollTimer: number = -1
  /** P19a: 消息列表滚动控制器（答案回流后滚底） */
  private scroller: Scroller = new Scroller()

  private readonly modelOptions: string[] = ['agnes-3.0-flash', 'agnes-3.0-pro', 'glm-4.7', '自定义(取配置)', '管理供应商…']

  aboutToAppear(): void {
    this.agents = AgentEngine.getAllAgentStatus()
    this.messages.push({
      role: 'hint',
      text: '给代理描述任务，如：打开 example.com 并告诉我页面标题',
      agentId: ''
    })
    console.info('AgentSidePanel mounted, agents=' + this.agents.length)
    this.startSettlePolling()
  }

  aboutToDisappear(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer)
      this.pollTimer = -1
      console.info('AgentSidePanel settle polling stopped')
    }
  }

  /** P19a: 轮询本面板派发过的 agent 终态，答案/失败原因回流成气泡 */
  private startSettlePolling(): void {
    this.pollTimer = setInterval(() => {
      this.pollSettled()
    }, 1000)
  }

  private pollSettled(): void {
    let changed = false
    for (const msg of this.messages) {
      if (msg.agentId.length > 0) {
        this.settledAgents.add(msg.agentId)
      }
    }
    for (const st of this.agents) {
      const id = st.agentId
      if (this.settledAgents.has(id)) {
        continue
      }
      if (st.status === AgentStatus.COMPLETED) {
        const ans = AgentEngine.getFinalAnswer(id)
        const text = ans !== null ? (ans.length > 500 ? ans.substring(0, 500) + '…' : ans) : '(已完成)'
        this.messages.push({ role: 'agent', text: text, agentId: id })
        this.settledAgents.add(id)
        changed = true
        console.info('AgentSidePanel answer reflux agent=' + id + ' len=' + text.length)
      } else if (st.status === AgentStatus.ERROR || st.status === AgentStatus.STOPPED) {
        const reason = st.errorMessage.length > 0 ? st.errorMessage : (AgentEngine.getFinalAnswer(id) ?? '任务已终止')
        this.messages.push({ role: 'hint', text: '⚠ ' + reason, agentId: id })
        this.settledAgents.add(id)
        changed = true
        console.info('AgentSidePanel fail reflux agent=' + id + ' reason=' + reason)
      }
    }
    if (changed) {
      this.agents = AgentEngine.getAllAgentStatus()
      // 新气泡推入后滚到底部（下一帧执行，确保布局已更新）
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Bottom)
      }, 50)
    }
  }

  private sendTask(): void {
    const task = this.inputText.trim()
    if (task.length === 0) {
      return
    }
    // ref1 模式：侧栏任务驱动活动 tab —— 无目标 URL 时用配置端点页兜底
    const cfg = ConfigManager.get()
    const targetUrl = cfg.llmBaseUrl.length > 0 ? cfg.llmBaseUrl : 'https://example.com'
    this.messages.push({ role: 'user', text: task, agentId: '' })
    const agent = AgentEngine.createAgent('sidepanel', targetUrl, task, RunStrategy.ONCE)
    if (agent) {
      this.messages.push({
        role: 'hint',
        text: `代理已启动 (${agent.agentId.substring(0, 12)}…) —— 驾驶舱磁贴与活动 tab 实时联动`,
        agentId: agent.agentId
      })
      this.agents = AgentEngine.getAllAgentStatus()
      this.inputText = ''
      console.info('AgentSidePanel task dispatched: ' + task + ' agent=' + agent.agentId)
    } else {
      this.messages.push({ role: 'hint', text: '代理创建失败（已达上限或 LLM 未配置）', agentId: '' })
      console.warn('AgentSidePanel createAgent returned null')
    }
  }

  /** P21b: 切到 history 视图并拉取会话列表(每次进入拉一次,数据量小不做下拉) */
  private switchToHistory(): void {
    this.panelView = 'history'
    this.refreshHistory()
  }

  /** P21b: 拉取会话列表(活跃内存 + 磁盘历史,startTime 降序) */
  private async refreshHistory(): Promise<void> {
    this.historyLoading = true
    try {
      const list = await SessionManager.getSessionListAsync()
      this.historySessions = list
      console.info('AgentSidePanel history loaded: ' + list.length + ' sessions')
    } catch (e) {
      console.warn('AgentSidePanel history load failed: ' + e)
    } finally {
      this.historyLoading = false
    }
  }

  /** P21b: 任务描述行——优先 agent 配置的 taskDescription,无则回退 URL 序列或 agentId */
  private sessionLabel(s: SessionRecord): string {
    const cfg = AgentEngine.getAgentConfig(s.agentId)
    if (cfg && cfg.taskDescription.length > 0) {
      return cfg.taskDescription
    }
    if (s.urlSequence.length > 0 && s.urlSequence[0].length > 0) {
      return s.urlSequence[0]
    }
    return s.agentId.length > 0 ? s.agentId : s.sessionId
  }

  /** P21b: 会话时间描述(上游 dayjs.fromNow 风格:今天 HH:mm / 昨天 / MM-DD / YYYY-MM-DD) */
  private sessionTimeLabel(t: number): string {
    if (t <= 0) {
      return ''
    }
    const d = new Date(t)
    const now = new Date()
    const pad = (n: number): string => (n < 10 ? '0' + n : '' + n)
    const sameDay = (a: Date, b: Date): boolean =>
      a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
    if (sameDay(d, now)) {
      return `今天 ${pad(d.getHours())}:${pad(d.getMinutes())}`
    }
    if (sameDay(d, yesterday)) {
      return `昨天 ${pad(d.getHours())}:${pad(d.getMinutes())}`
    }
    if (d.getFullYear() === now.getFullYear()) {
      return `${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    }
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  }

  /** P21b: 点历史行 → 回放页 */
  private openSession(s: SessionRecord): void {
    console.info('AgentSidePanel open session replay: ' + s.sessionId)
    router.pushUrl({ url: 'pages/SessionPlayerPage', params: { sessionId: s.sessionId } })
  }

  build(): void {
    Column() {
      // 顶部标题栏（对齐上游 ChatHeader：左 Agent 标题+视图切换，右 模型下拉+⚙+关闭）
      Row() {
        Text('Agent')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)

        // 视图切换（上游：非 history 页显示 History 图标钮；history 页换成 Plus 回到新会话）
        if (this.panelView === 'chat') {
          Image($r('app.media.ic_history'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
            .width(28)
            .accessibilityText('查看历史会话')
            .onClick(() => {
              this.switchToHistory()
            })
        } else {
          Image($r('app.media.ic_add'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
            .width(28)
            .accessibilityText('新建对话')
            .onClick(() => {
              this.panelView = 'chat'
            })
        }

        Blank()

        // 模型下拉（简化：点击循环切换）
        Text(this.modelOptions[this.modelSelection])
          .fontSize(11)
          .fontColor('#1A73E8')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 110 })
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(this.pal().selected)
          .onClick(() => {
            this.modelSelection = (this.modelSelection + 1) % this.modelOptions.length
            if (this.modelOptions[this.modelSelection] === '管理供应商…') {
              // p23b: 循环到管理项 = 跳 LLM Hub，选择回退保持原模型显示
              router.pushUrl({ url: 'pages/LlmHubPage' })
              this.modelSelection = 0
              return
            }
            console.info('AgentSidePanel model switch: ' + this.modelOptions[this.modelSelection])
          })

        Image($r('app.media.ic_settings'))
          .width(16).height(16)
          .fillColor(this.pal().text2)
          .draggable(false)
          .width(28)

        Image($r('app.media.ic_close'))
          .width(16).height(16)
          .fillColor(this.pal().text2)
          .draggable(false)
          .width(28)
          .accessibilityText('关闭代理侧栏')
          .onClick(() => {
            this.onClose()
          })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 8 })
      .backgroundColor(this.pal().surfaceAlt)
      .border({ width: { bottom: 1 }, color: this.pal().border })

      // 主体：chat 视图（消息列表 + 输入区） / history 视图（会话历史列表,上游 ChatHistory）
      if (this.panelView === 'chat') {
        // 消息列表
        List({ scroller: this.scroller }) {
          ForEach(this.messages, (msg: ChatMessage, index: number) => {
            ListItem() {
              if (msg.role === 'user') {
                // 用户右气泡
                Row() {
                  Blank()
                  Text(msg.text)
                    .fontSize(13)
                    .fontColor('#FFFFFF')
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .borderRadius(12)
                    .backgroundColor('#1A73E8')
                    .constraintSize({ maxWidth: 260 })
                }
                .width('100%')
              } else {
                // 助手/系统左卡(P21b: surface 卡片,与 surfaceAlt 面板底区分)
                Row() {
                  Text(msg.text)
                    .fontSize(12)
                    .fontColor(this.pal().text2)
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .borderRadius(12)
                    .backgroundColor(this.pal().surface)
                    .constraintSize({ maxWidth: 260 })
                }
                .width('100%')
              }
            }
            .padding({ top: 4, bottom: 4 })
          }, (msg: ChatMessage, index: number) => index + '_' + msg.text)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 12, right: 12 })
        .scrollBar(BarState.Off)
        // P21b: chat 内容区与面板底同色(surfaceAlt),气泡用 surface 卡片区分
        .backgroundColor(this.pal().surfaceAlt)

        // 底部输入区
        Column() {
          TextArea({ text: this.inputText, placeholder: '描述代理任务…' })
            .width('100%')
            .height(72)
            .fontSize(13)
            .backgroundColor(this.pal().surfaceAlt)
            .borderRadius(10)
            .onChange((v: string) => {
              this.inputText = v
            })
          Row() {
            Text(`${this.agents.length} 个代理在跑`)
              .fontSize(10)
              .fontColor('#9AA0A6')
              .layoutWeight(1)
            Button('发送')
              .fontSize(13)
              .height(32)
              .backgroundColor('#1A73E8')
              .fontColor('#FFFFFF')
              .borderRadius(16)
              .onClick(() => {
                this.sendTask()
              })
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .padding({ top: 8, bottom: 10 })
        .backgroundColor(this.pal().surface)
        .border({ width: { top: 1 }, color: this.pal().border })
      } else {
        // ===== history 视图（上游 ChatHistory：时间分组会话列表 + 空态引导）=====
        if (this.historyLoading && this.historySessions.length === 0) {
          Column() {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(this.pal().text2)
            Text('正在获取会话…')
              .fontSize(12)
              .fontColor(this.pal().text2)
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.historySessions.length === 0) {
          // 空态（上游：MessageSquare 图标 + emptyMessage + "Start a new chat" 链接）
          Column() {
            Image($r('app.media.ic_robot'))
              .width(40)
              .height(40)
              .fillColor(this.pal().text2)
              .opacity(0.5)
              .draggable(false)
            Text('暂无历史会话')
              .fontSize(14)
              .fontColor(this.pal().text2)
              .margin({ top: 12 })
            Text('开始新对话')
              .fontSize(13)
              .fontColor('#1A73E8')
              .margin({ top: 8 })
              .onClick(() => {
                this.panelView = 'chat'
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.historySessions, (s: SessionRecord) => {
              ListItem() {
                Row() {
                  Image($r('app.media.ic_robot'))
                    .width(18).height(18)
                    .fillColor(this.pal().text2)
                    .draggable(false)
                    .margin({ right: 10 })
                  Column() {
                    Text(this.sessionLabel(s))
                      .fontSize(13)
                      .fontColor(this.pal().text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.sessionTimeLabel(s.startTime) + ' · ' + s.operationLogs.length + ' 步')
                      .fontSize(10)
                      .fontColor(this.pal().text2)
                      .margin({ top: 2 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(8)
                .onClick(() => {
                  this.openSession(s)
                })
              }
            }, (s: SessionRecord) => s.sessionId)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 8, right: 8, top: 4 })
          .scrollBar(BarState.Off)
          .divider({
            strokeWidth: 1,
            color: this.pal().border,
            startMargin: 40,
            endMargin: 0
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    // P21b: 面板底色与浏览器 chrome 区分——surfaceAlt(内容区同色),左侧细分隔线对齐上游风格
    .backgroundColor(this.pal().surfaceAlt)
  }
}
