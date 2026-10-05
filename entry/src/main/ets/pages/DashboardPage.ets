import { AgentEngine } from '../service/AgentEngine'
import { AgentStatusInfo } from '../model/AgentStatus'
import { AgentStatus } from '../common/Types'
import { ConnectionManager } from '../service/ConnectionManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'

interface AgentCardParams {
  status: AgentStatusInfo
}

@Entry
@Component
struct DashboardPage {
  @State agentStatuses: AgentStatusInfo[] = []
  @State connectedTools: string[] = []
  @State memoryUsage: string = '0 MB'
  @State diskSpace: string = '0 GB'

  aboutToAppear(): void {
    this.agentStatuses = AgentEngine.getAllAgentStatus()
    this.connectedTools = ConnectionManager.getConnectedTools().map(t => t.displayName)
    EventBus.on(EventBusEvents.AGENT_STATUS_CHANGE, this.onAgentStatusChange)
    EventBus.on(EventBusEvents.AGENT_HEARTBEAT, this.onAgentHeartbeat)
    EventBus.on(EventBusEvents.MCP_CONNECTION_CHANGE, this.onConnectionChange)
  }

  aboutToDisappear(): void {
    EventBus.off(EventBusEvents.AGENT_STATUS_CHANGE, this.onAgentStatusChange)
    EventBus.off(EventBusEvents.AGENT_HEARTBEAT, this.onAgentHeartbeat)
    EventBus.off(EventBusEvents.MCP_CONNECTION_CHANGE, this.onConnectionChange)
  }

  private onAgentStatusChange = (data: Object): void => {
    this.agentStatuses = AgentEngine.getAllAgentStatus()
  }

  private onAgentHeartbeat = (data: Object): void => {
    this.agentStatuses = AgentEngine.getAllAgentStatus()
  }

  private onConnectionChange = (data: Object): void => {
    this.connectedTools = ConnectionManager.getConnectedTools().map(t => t.displayName)
  }

  build(): void {
    Column() {
      Text('仪表盘')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ top: 16, bottom: 16 })

      if (this.agentStatuses.length === 0) {
        Column() {
          Text('暂无运行中的AI代理')
            .fontSize(16)
            .fontColor('#999999')
            .margin({ top: 40 })

          Text('连接AI工具后即可开始使用')
            .fontSize(12)
            .fontColor('#BBBBBB')
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.agentStatuses, (status: AgentStatusInfo) => {
            ListItem() {
              this.AgentCard({ status: status })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      }

      this.ConnectionPanel()
      this.SystemStatus()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  AgentCard($$: AgentCardParams): void {
    Column() {
      Row() {
        Text($$.status.agentId.substring(0, 20))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .layoutWeight(1)

        Text(this.getStatusText($$.status.status))
          .fontSize(12)
          .fontColor(this.getStatusColor($$.status.status))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.getStatusBgColor($$.status.status))
      }
      .width('100%')

      Row() {
        Text('运行时长: ')
          .fontSize(12)
          .fontColor('#666666')
        Text(this.formatDuration($$.status.runningDuration))
          .fontSize(12)
          .fontColor('#333333')

        Text('  进度: ')
          .fontSize(12)
          .fontColor('#666666')
        Text(`${$$.status.progress}%`)
          .fontSize(12)
          .fontColor('#333333')
      }
      .width('100%')
      .margin({ top: 8 })

      if ($$.status.currentUrl) {
        Text($$.status.currentUrl)
          .fontSize(12)
          .fontColor('#007DFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }

      if ($$.status.errorMessage) {
        Text($$.status.errorMessage)
          .fontSize(12)
          .fontColor('#F44336')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }

      Row() {
        if ($$.status.status === AgentStatus.RUNNING) {
          Button('停止')
            .fontSize(12)
            .height(28)
            .backgroundColor('#F44336')
            .onClick(() => {
              AgentEngine.terminateAgent($$.status.agentId)
            })
        }

        Button('详情')
          .fontSize(12)
          .height(28)
          .backgroundColor('#007DFF')
          .margin({ left: 8 })
          .onClick(() => {
          })
      }
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor('#F8F8F8')
    .margin({ bottom: 8 })
  }

  @Builder
  ConnectionPanel(): void {
    Column() {
      Text('AI工具连接')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 8 })

      if (this.connectedTools.length === 0) {
        Text('未检测到已连接的AI工具')
          .fontSize(12)
          .fontColor('#999999')
      } else {
        Row() {
          ForEach(this.connectedTools, (tool: string) => {
            Row() {
              Text(tool)
                .fontSize(12)
                .fontColor('#4CAF50')
              Text(' 已连接')
                .fontSize(10)
                .fontColor('#4CAF50')
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(4)
            .backgroundColor('#E8F5E9')
            .margin({ right: 8 })
          })
        }
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor('#F8F8F8')
    .margin({ top: 8 })
  }

  @Builder
  SystemStatus(): void {
    Row() {
      Text(`内存: ${this.memoryUsage}`)
        .fontSize(12)
        .fontColor('#666666')

      Text(`磁盘: ${this.diskSpace}`)
        .fontSize(12)
        .fontColor('#666666')
        .margin({ left: 16 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
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

  private getStatusBgColor(status: AgentStatus): string {
    switch (status) {
      case AgentStatus.IDLE:
        return '#F0F0F0'
      case AgentStatus.RUNNING:
        return '#E6F2FF'
      case AgentStatus.COMPLETED:
        return '#E8F5E9'
      case AgentStatus.ERROR:
        return '#FFEBEE'
      case AgentStatus.STOPPED:
        return '#EEEEEE'
      case AgentStatus.PAUSED:
        return '#FFF3E0'
      default:
        return '#F0F0F0'
    }
  }

  private formatDuration(ms: number): string {
    const seconds = Math.floor(ms / 1000)
    const minutes = Math.floor(seconds / 60)
    const hours = Math.floor(minutes / 60)
    if (hours > 0) {
      return `${hours}h ${minutes % 60}m`
    }
    if (minutes > 0) {
      return `${minutes}m ${seconds % 60}s`
    }
    return `${seconds}s`
  }
}