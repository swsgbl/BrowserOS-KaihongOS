import { SensitiveOperationType } from '../common/Types'

@Component
export struct ConfirmDialog {
  @State isVisible: boolean = false
  @State agentId: string = ''
  @State operationType: SensitiveOperationType = SensitiveOperationType.FORM_SUBMIT
  @State targetUrl: string = ''
  @State targetElement: string = ''
  onConfirm?: (agentId: string, operationType: SensitiveOperationType) => void
  onReject?: (agentId: string, operationType: SensitiveOperationType) => void

  show(agentId: string, operationType: SensitiveOperationType, targetUrl: string, targetElement: string): void {
    this.agentId = agentId
    this.operationType = operationType
    this.targetUrl = targetUrl
    this.targetElement = targetElement
    this.isVisible = true
  }

  hide(): void {
    this.isVisible = false
  }

  build(): void {
    if (this.isVisible) {
      Column() {
        Column() {
          Text('敏感操作确认')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .margin({ top: 16 })

          Text(this.getOperationDescription())
            .fontSize(14)
            .fontColor('#666666')
            .margin({ top: 12 })

          Column() {
            Row() {
              Text('代理: ')
                .fontSize(12)
                .fontColor('#999999')
              Text(this.agentId.substring(0, 20))
                .fontSize(12)
                .fontColor('#333333')
            }

            if (this.targetUrl) {
              Row() {
                Text('目标URL: ')
                  .fontSize(12)
                  .fontColor('#999999')
                Text(this.targetUrl)
                  .fontSize(12)
                  .fontColor('#007DFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .margin({ top: 4 })
            }

            if (this.targetElement) {
              Row() {
                Text('目标元素: ')
                  .fontSize(12)
                  .fontColor('#999999')
                Text(this.targetElement)
                  .fontSize(12)
                  .fontColor('#333333')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .margin({ top: 4 })
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(8)
          .backgroundColor('#F8F8F8')
          .margin({ top: 16 })

          Row() {
            Button('拒绝')
              .fontSize(14)
              .width(100)
              .height(40)
              .backgroundColor('#F44336')
              .onClick(() => {
                if (this.onReject) {
                  this.onReject(this.agentId, this.operationType)
                }
                this.hide()
              })

            Button('确认')
              .fontSize(14)
              .width(100)
              .height(40)
              .backgroundColor('#4CAF50')
              .margin({ left: 12 })
              .onClick(() => {
                if (this.onConfirm) {
                  this.onConfirm(this.agentId, this.operationType)
                }
                this.hide()
              })
          }
          .margin({ top: 24, bottom: 16 })
        }
        .width('80%')
        .borderRadius(12)
        .backgroundColor('#FFFFFF')
        .padding(16)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  private getOperationDescription(): string {
    switch (this.operationType) {
      case SensitiveOperationType.FORM_SUBMIT:
        return 'AI代理尝试提交表单，请确认是否允许此操作'
      case SensitiveOperationType.PAYMENT:
        return 'AI代理尝试执行支付操作，请确认是否允许此操作'
      case SensitiveOperationType.DELETE:
        return 'AI代理尝试执行删除操作，请确认是否允许此操作'
      case SensitiveOperationType.SETTINGS_CHANGE:
        return 'AI代理尝试修改安全设置，请确认是否允许此操作'
      case SensitiveOperationType.UNSPECIFIED_NAVIGATION:
        return 'AI代理尝试导航到未指定的URL，请确认是否允许此操作'
      default:
        return 'AI代理尝试执行敏感操作，请确认是否允许'
    }
  }
}