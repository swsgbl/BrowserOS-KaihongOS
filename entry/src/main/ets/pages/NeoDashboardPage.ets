import { AgentEngine } from '../service/AgentEngine'
import { AgentStatusInfo } from '../model/AgentStatus'
import { AgentStatus, RunStrategy } from '../common/Types'
import { ConnectionManager } from '../service/ConnectionManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'

@Entry
@Component
struct NeoDashboardPage {
  @State agentStatuses: AgentStatusInfo[] = []
  @State connectedTools: string[] = []
  @State newAgentName: string = ''
  @State newAgentUrl: string = ''
  @State newAgentTask: string = ''

  aboutToAppear(): void {
    this.agentStatuses = AgentEngine.getAllAgentStatus()
    this.connectedTools = ConnectionManager.getConnectedTools().map(t => t.displayName)
    EventBus.on(EventBusEvents.AGENT_STATUS_CHANGE, this.onAgentStatusChange)
  }

  aboutToDisappear(): void {
    EventBus.off(EventBusEvents.AGENT_STATUS_CHANGE, this.onAgentStatusChange)
  }

  private onAgentStatusChange = (data: Object): void => {
    this.agentStatuses = AgentEngine.getAllAgentStatus()
  }

  build(): void {
    Column() {
      Text('BrowserOS neo')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ top: 16 })

      Text('AI代理驱动浏览器 - 深开鸿版本')
        .fontSize(12)
        .fontColor('#666666')
        .margin({ top: 4 })

      this.AgentCreationPanel()

      this.AgentList()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  AgentCreationPanel(): void {
    Column() {
      Text('创建新代理')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
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
        .backgroundColor('#007DFF')
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
    .backgroundColor('#F8F8F8')
    .margin({ top: 16 })
  }

  @Builder
  AgentList(): void {
    Column() {
      Text('代理列表')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 8 })

      if (this.agentStatuses.length === 0) {
        Text('暂无代理')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 24 })
      } else {
        List() {
          ForEach(this.agentStatuses, (status: AgentStatusInfo) => {
            ListItem() {
              Row() {
                Column() {
                  Text(status.agentId.substring(0, 20))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333')

                  Text(this.getStatusText(status.status))
                    .fontSize(10)
                    .fontColor(this.getStatusColor(status.status))
                    .margin({ top: 4 })
                }
                .layoutWeight(1)

                if (status.status === AgentStatus.RUNNING) {
                  Button('停止')
                    .fontSize(10)
                    .height(24)
                    .backgroundColor('#F44336')
                    .onClick(() => {
                      AgentEngine.terminateAgent(status.agentId)
                    })
                }
              }
              .width('100%')
              .padding(8)
              .borderRadius(4)
              .backgroundColor('#FFFFFF')
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