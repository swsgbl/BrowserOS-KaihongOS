import { AgentEngine } from '../service/AgentEngine'
import { AgentStatusInfo } from '../model/AgentStatus'
import { AgentStatus, RunStrategy } from '../common/Types'
import { ConnectionManager } from '../service/ConnectionManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ConfigManager } from '../storage/ConfigManager'
import { TabManager } from '../service/TabManager'

/**
 * P6: NeoDashboard 内嵌覆盖层组件（BrowserShell 内 Stack zIndex 覆盖）。
 * 从 NeoDashboardPage(router) 改造而来 —— 治「router 覆盖态下 BrowserShell
 * @State 不驱动渲染、agent tab 的 Web 组件不挂载」的根因。
 * shellBack: 关闭面板回到浏览器主体；shellOpenReplay: 打开回放页（router 到 SessionPlayerPage）。
 */
@Component
export struct NeoDashboardPanel {
  @State agentStatuses: AgentStatusInfo[] = []
  @State connectedTools: string[] = []
  @State newAgentName: string = ''
  @State newAgentUrl: string = ''
  @State newAgentTask: string = ''
  @State showLlmSettings: boolean = false
  @State llmBaseUrlInput: string = ''
  @State llmApiKeyInput: string = ''
  @State llmModelInput: string = ''
  @State llmSaveHint: string = ''
  shellBack: () => void = () => {}
  shellOpenReplay: (sessionId: string) => void = () => {}

  aboutToAppear(): void {
    this.agentStatuses = AgentEngine.getAllAgentStatus()
    this.connectedTools = ConnectionManager.getConnectedTools().map(t => t.displayName)
    const cfg = ConfigManager.get()
    this.llmBaseUrlInput = cfg.llmBaseUrl
    this.llmApiKeyInput = cfg.llmApiKey
    this.llmModelInput = cfg.llmModel
    EventBus.on(EventBusEvents.AGENT_STATUS_CHANGE, this.onAgentStatusChange)
    EventBus.on(EventBusEvents.AGENT_HEARTBEAT, this.onAgentStatusChange)
    console.info('NeoDashboardPanel mounted (in-shell overlay)')
  }

  aboutToDisappear(): void {
    EventBus.off(EventBusEvents.AGENT_STATUS_CHANGE, this.onAgentStatusChange)
    EventBus.off(EventBusEvents.AGENT_HEARTBEAT, this.onAgentStatusChange)
  }

  private onAgentStatusChange = (data: Object): void => {
    this.agentStatuses = AgentEngine.getAllAgentStatus()
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

  build(): void {
    Column() {
      Row() {
        Button('← 返回')
          .fontSize(14)
          .height(32)
          .backgroundColor('#999999')
          .onClick(() => {
            console.info('NeoDashboardPanel back clicked')
            this.shellBack()
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ top: 12 })

      Text('BrowserOS neo')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E6EDF3')
        .margin({ top: 8 })

      Text('AI代理驱动浏览器 - 深开鸿版本')
        .fontSize(12)
        .fontColor('#8B949E')
        .margin({ top: 4 })

      this.LlmSettingsEntry()

      if (this.showLlmSettings) {
        this.LlmSettingsPanel()
      }

      this.AgentCreationPanel()

      this.AgentList()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0D1117')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  LlmSettingsEntry(): void {
    Row() {
      Text('LLM 设置')
        .fontSize(14)
        .fontColor('#007DFF')
      if (ConfigManager.get().llmBaseUrl.length > 0) {
        Text(` (已配置: ${ConfigManager.get().llmBaseUrl})`)
          .fontSize(10)
          .fontColor('#3FB950')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 180 })
      } else {
        Text(' (未配置)')
          .fontSize(10)
          .fontColor('#F85149')
      }
    }
    .width('100%')
    .height(36)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor('#161B22')
    .margin({ top: 12 })
    .onClick(() => {
      this.showLlmSettings = !this.showLlmSettings
    })
  }

  @Builder
  LlmSettingsPanel(): void {
    Column() {
      Text('LLM 接入（OpenAI 兼容）')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E6EDF3')
        .margin({ bottom: 8 })

      TextInput({ text: this.llmBaseUrlInput, placeholder: 'API 端点，如 http://10.0.2.2:11434/v1' })
        .width('100%')
        .height(36)
        .onChange((value: string) => {
          this.llmBaseUrlInput = value
        })

      TextInput({ text: this.llmApiKeyInput, placeholder: 'API Key（本地服务可留空）' })
        .width('100%')
        .height(36)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.llmApiKeyInput = value
        })

      TextInput({ text: this.llmModelInput, placeholder: '模型名，如 qwen3.8:latest' })
        .width('100%')
        .height(36)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.llmModelInput = value
        })

      if (this.llmApiKeyInput.length > 0) {
        Text(`Key: ${this.maskKey(this.llmApiKeyInput)}`)
          .fontSize(10)
          .fontColor('#8B949E')
          .margin({ top: 4 })
      }

      Row() {
        Button('保存')
          .fontSize(14)
          .height(36)
          .backgroundColor('#1F6FEB')
          .onClick(async () => {
            const ok = await ConfigManager.update({
              llmBaseUrl: this.llmBaseUrlInput,
              llmApiKey: this.llmApiKeyInput,
              llmModel: this.llmModelInput
            })
            if (ok) {
              this.llmSaveHint = '已保存'
            } else {
              this.llmSaveHint = '保存失败：配置校验未通过'
            }
          })

        if (this.llmSaveHint.length > 0) {
          Text(this.llmSaveHint)
            .fontSize(12)
            .fontColor(this.llmSaveHint === '已保存' ? '#4CAF50' : '#F44336')
            .margin({ left: 12 })
        }
      }
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor('#161B22')
    .margin({ top: 8 })
  }

  @Builder
  AgentCreationPanel(): void {
    Column() {
      Text('创建新代理')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E6EDF3')
        .margin({ bottom: 8 })

      TextInput({ placeholder: '代理名称' })
        .width('100%')
        .height(36)
        .onChange((value: string) => {
          this.newAgentName = value
        })

      TextInput({ placeholder: '目标URL' })
        .width('100%')
        .height(36)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.newAgentUrl = value
        })

      TextInput({ placeholder: '任务描述' })
        .width('100%')
        .height(36)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.newAgentTask = value
        })

      Button('创建代理')
        .fontSize(14)
        .width('100%')
        .height(40)
        .backgroundColor('#1F6FEB')
        .margin({ top: 12 })
        .onClick(() => {
          if (this.newAgentName && this.newAgentUrl) {
            AgentEngine.createAgent(
              this.newAgentName,
              this.newAgentUrl,
              this.newAgentTask,
              RunStrategy.ONCE
            )
            this.newAgentName = ''
            this.newAgentUrl = ''
            this.newAgentTask = ''
            this.agentStatuses = AgentEngine.getAllAgentStatus()
          }
        })
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor('#161B22')
    .margin({ top: 16 })
  }

  @Builder
  AgentList(): void {
    Column() {
      Text('代理列表')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E6EDF3')
        .margin({ bottom: 8 })

      if (this.agentStatuses.length === 0) {
        Text('暂无代理')
          .fontSize(14)
          .fontColor('#8B949E')
          .margin({ top: 24 })
      } else {
        List() {
          ForEach(this.agentStatuses, (status: AgentStatusInfo) => {
            ListItem() {
              Column() {
                Row() {
                  Text(status.agentId.substring(0, 20))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#E6EDF3')
                    .layoutWeight(1)

                  Text(this.getStatusText(status.status))
                    .fontSize(10)
                    .fontColor(this.getStatusColor(status.status))

                  if (status.status === AgentStatus.RUNNING) {
                    Button('停止')
                      .fontSize(10)
                      .height(24)
                      .backgroundColor('#F44336')
                      .margin({ left: 8 })
                      .onClick(() => {
                        AgentEngine.terminateAgent(status.agentId)
                      })
                  }
                }
                .width('100%')

                Text(`URL: ${this.getAgentUrl(status.agentId) || '(空)'}`)
                  .fontSize(10)
                  .fontColor('#8B949E')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 4 })

                Text(`进度: ${status.progress}%`)
                  .fontSize(10)
                  .fontColor('#007DFF')
                  .margin({ top: 2 })

                Text(`活动: ${AgentEngine.getAgentActivity(status.agentId) || '(无)'}`)
                  .fontSize(10)
                  .fontColor('#8B949E')
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })

                if (status.status === AgentStatus.COMPLETED || status.status === AgentStatus.ERROR) {
                  Button('回放')
                    .fontSize(10)
                    .height(24)
                    .backgroundColor('#9E6A03')
                    .margin({ top: 4 })
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

                if (status.status === AgentStatus.ERROR && status.errorMessage.length > 0) {
                  Text(`错误: ${status.errorMessage}`)
                    .fontSize(10)
                    .fontColor('#F85149')
                    .margin({ top: 2 })
                }
              }
              .width('100%')
              .padding(8)
              .borderRadius(4)
              .backgroundColor('#0D1117')
              .margin({ top: 4 })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .margin({ top: 16 })
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
      case AgentStatus.IDLE:
        return '#999999'
      case AgentStatus.RUNNING:
        return '#007DFF'
      case AgentStatus.COMPLETED:
        return '#4CAF50'
      case AgentStatus.ERROR:
        return '#F44336'
      case AgentStatus.STOPPED:
        return '#9E9E9E'
      case AgentStatus.PAUSED:
        return '#FF9800'
      default:
        return '#999999'
    }
  }
}
