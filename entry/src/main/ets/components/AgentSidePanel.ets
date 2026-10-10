/**
 * P9-B: Agent 侧边面板（ref1 一比一复刻）
 * 右侧 360vp 常驻面板：顶部标题栏（Agent + 模型下拉 + ⚙）+ 消息气泡列表
 * + 底部多行输入 + 发送。发送 = AgentEngine.createAgent（与 Dashboard 磁贴联动）。
 */
import { AgentEngine } from '../service/AgentEngine'
import { ConfigManager } from '../storage/ConfigManager'
import { RunStrategy, AgentStatus } from '../common/Types'
import { AgentStatusInfo } from '../model/AgentStatus'
import { Palette } from '../common/Palette'

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
  onClose: () => void = () => {}
  /** P19a: 已回流过终态的 agent（去重，避免轮询重复推气泡） */
  private settledAgents: Set<string> = new Set()
  /** P19a: 终态轮询句柄（aboutToDisappear 必清） */
  private pollTimer: number = -1
  /** P19a: 消息列表滚动控制器（答案回流后滚底） */
  private scroller: Scroller = new Scroller()

  private readonly modelOptions: string[] = ['agnes-3.0-flash', 'agnes-3.0-pro', 'glm-4.7', '自定义(取配置)']

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

  build(): void {
    Column() {
      // 顶部标题栏：Agent + 模型下拉 + ⚙ + 关闭
      Row() {
        Text('Agent')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().text)
          .layoutWeight(1)

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
              // 助手/系统左白卡
              Row() {
                Text(msg.text)
                  .fontSize(12)
                  .fontColor(this.pal().text2)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .borderRadius(12)
                  .backgroundColor(this.pal().surfaceAlt)
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().surface)
  }
}
