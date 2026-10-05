import { AgentStatusInfo } from '../model/AgentStatus'
import { AgentStatus } from '../common/Types'

@Component
export struct AgentCard {
  @State status: AgentStatusInfo = new AgentStatusInfo('')
  @State isExpanded: boolean = false
  onStop?: (agentId: string) => void
  onDetail?: (agentId: string) => void

  build(): void {
    Column() {
      Row() {
        Text(this.status.agentId.substring(0, 20))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .layoutWeight(1)

        Text(this.getStatusText(this.status.status))
          .fontSize(12)
          .fontColor(this.getStatusColor(this.status.status))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.getStatusBgColor(this.status.status))
      }
      .width('100%')

      Row() {
        Text('运行时长: ')
          .fontSize(12)
          .fontColor('#666666')
        Text(this.formatDuration(this.status.runningDuration))
          .fontSize(12)
          .fontColor('#333333')

        Text('  进度: ')
          .fontSize(12)
          .fontColor('#666666')
        Text(`${this.status.progress}%`)
          .fontSize(12)
          .fontColor('#333333')
      }
      .width('100%')
      .margin({ top: 8 })

      if (this.status.currentUrl) {
        Text(this.status.currentUrl)
          .fontSize(12)
          .fontColor('#007DFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }

      if (this.status.errorMessage) {
        Text(this.status.errorMessage)
          .fontSize(12)
          .fontColor('#F44336')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }

      Row() {
        if (this.status.status === AgentStatus.RUNNING) {
          Button('停止')
            .fontSize(12)
            .height(28)
            .backgroundColor('#F44336')
            .onClick(() => {
              if (this.onStop) {
                this.onStop(this.status.agentId)
              }
            })
        }

        Button('详情')
          .fontSize(12)
          .height(28)
          .backgroundColor('#007DFF')
          .margin({ left: 8 })
          .onClick(() => {
            this.isExpanded = !this.isExpanded
            if (this.onDetail) {
              this.onDetail(this.status.agentId)
            }
          })
      }
      .margin({ top: 8 })

      if (this.isExpanded) {
        this.DetailPanel()
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor('#F8F8F8')
  }

  @Builder
  DetailPanel(): void {
    Column() {
      Text('操作详情')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ top: 8 })

      Text('当前URL:')
        .fontSize(10)
        .fontColor('#666666')
        .margin({ top: 4 })
      Text(this.status.currentUrl || '无')
        .fontSize(10)
        .fontColor('#007DFF')

      Text('最后心跳:')
        .fontSize(10)
        .fontColor('#666666')
        .margin({ top: 4 })
      Text(new Date(this.status.lastHeartbeat).toLocaleTimeString())
        .fontSize(10)
        .fontColor('#333333')
    }
    .width('100%')
    .padding(8)
    .borderRadius(4)
    .backgroundColor('#EEEEEE')
    .margin({ top: 8 })
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