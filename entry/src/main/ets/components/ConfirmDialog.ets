import { SensitiveOperationType } from '../common/Types'
import { I18n } from '../common/I18n'
import { EventBus, EventBusEvents } from '../infra/EventBus'

@Component
export struct ConfirmDialog {
  // P48: locale 刷新锚
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }
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

  /** P5: 事件结构（SENSITIVE_OPERATION_DETECTED 载荷） */
  static readonly EVENT_DETECTED: string = 'sensitive_operation_detected'

  aboutToAppear(): void {
    // P5: 自监听敏感操作事件（BrowserShell 挂载本组件即闭环 requestConfirmation）
    EventBus.on(EventBusEvents.SENSITIVE_OPERATION_DETECTED, this.onDetected)
    console.info('ConfirmDialog mounted, listening SENSITIVE_OPERATION_DETECTED')
  }

  aboutToDisappear(): void {
    EventBus.off(EventBusEvents.SENSITIVE_OPERATION_DETECTED, this.onDetected)
  }

  private onDetected = (data: Object): void => {
    try {
      const detail = data as Record<string, Object>
      const agentId = detail['agentId'] as string
      const operationType = detail['operationType'] as SensitiveOperationType
      const targetUrl = (detail['targetUrl'] as string) || ''
      const targetElement = (detail['targetElement'] as string) || ''
      console.info('ConfirmDialog onDetected agent=' + agentId + ' type=' + operationType + ' url=' + targetUrl)
      this.show(agentId, operationType, targetUrl, targetElement)
    } catch (e) {
      console.error('ConfirmDialog onDetected error: ' + e)
    }
  }

  hide(): void {
    this.isVisible = false
  }

  build(): void {
    if (this.isVisible) {
      Column() {
        Column() {
          Text(I18n.t('dlgSensitiveTitle'))
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
              Text(I18n.t('dlgAgent'))
                .fontSize(12)
                .fontColor('#999999')
              Text(this.agentId.substring(0, 20))
                .fontSize(12)
                .fontColor('#333333')
            }

            if (this.targetUrl) {
              Row() {
                Text(I18n.t('dlgTargetUrl'))
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
                Text(I18n.t('dlgTargetEl'))
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
            Button(I18n.t('dlgDeny'))
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

            Button(I18n.t('confirm'))
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
        return I18n.getLocale() === 'en' ? 'The AI agent is trying to submit a form. Allow this operation?' : 'AI代理尝试提交表单，请确认是否允许此操作'
      case SensitiveOperationType.PAYMENT:
        return I18n.getLocale() === 'en' ? 'The AI agent is trying to make a payment. Allow this operation?' : 'AI代理尝试执行支付操作，请确认是否允许此操作'
      case SensitiveOperationType.DELETE:
        return I18n.getLocale() === 'en' ? 'The AI agent is trying to delete something. Allow this operation?' : 'AI代理尝试执行删除操作，请确认是否允许此操作'
      case SensitiveOperationType.SETTINGS_CHANGE:
        return I18n.getLocale() === 'en' ? 'The AI agent is trying to change security settings. Allow this operation?' : 'AI代理尝试修改安全设置，请确认是否允许此操作'
      case SensitiveOperationType.UNSPECIFIED_NAVIGATION:
        return I18n.getLocale() === 'en' ? 'The AI agent is trying to navigate to an unspecified URL. Allow this operation?' : 'AI代理尝试导航到未指定的URL，请确认是否允许此操作'
      default:
        return I18n.getLocale() === 'en' ? 'The AI agent is trying to perform a sensitive operation. Allow it?' : 'AI代理尝试执行敏感操作，请确认是否允许'
    }
  }
}