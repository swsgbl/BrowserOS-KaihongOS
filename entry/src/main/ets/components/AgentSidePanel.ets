/**
 * P9-B: Agent 侧边面板（ref1 一比一复刻）
 * 右侧 360vp 常驻面板：顶部标题栏（Agent + 模型下拉 + ⚙）+ 消息气泡列表
 * + 底部多行输入 + 发送。发送 = AgentEngine.createAgent（与 Dashboard 磁贴联动）。
 */
import { AgentEngine } from '../service/AgentEngine'
import { ConfigManager } from '../storage/ConfigManager'
import { RunStrategy } from '../common/Types'
import { AgentStatusInfo } from '../model/AgentStatus'

interface ChatMessage {
  role: string // 'user' | 'agent' | 'hint'
  text: string
  agentId: string
}

@Component
export struct AgentSidePanel {
  @State messages: ChatMessage[] = []
  @State inputText: string = ''
  @State modelSelection: number = 0
  @State agents: AgentStatusInfo[] = []
  @State showModelDropdown: boolean = false
  onClose: () => void = () => {}

  private readonly modelOptions: string[] = ['agnes-3.0-flash', 'agnes-3.0-pro', 'glm-4.7', '自定义(取配置)']

  aboutToAppear(): void {
    this.agents = AgentEngine.getAllAgentStatus()
    this.messages.push({
      role: 'hint',
      text: '给代理描述任务，如：打开 example.com 并告诉我页面标题',
      agentId: ''
    })
    console.info('AgentSidePanel mounted, agents=' + this.agents.length)
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
          .fontColor('#202124')
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
          .backgroundColor('#E8F0FE')
          .onClick(() => {
            this.modelSelection = (this.modelSelection + 1) % this.modelOptions.length
            console.info('AgentSidePanel model switch: ' + this.modelOptions[this.modelSelection])
          })

        Text('⚙')
          .fontSize(15)
          .fontColor('#5F6368')
          .width(28)
          .textAlign(TextAlign.Center)

        Text('×')
          .fontSize(16)
          .fontColor('#5F6368')
          .width(28)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onClose()
          })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 8 })
      .backgroundColor('#F1F3F4')
      .border({ width: { bottom: 1 }, color: '#E0E0E0' })

      // 消息列表
      List() {
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
                  .fontColor('#5F6368')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .borderRadius(12)
                  .backgroundColor('#F1F3F4')
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
          .backgroundColor('#F1F3F4')
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
      .backgroundColor('#FFFFFF')
      .border({ width: { top: 1 }, color: '#E0E0E0' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
