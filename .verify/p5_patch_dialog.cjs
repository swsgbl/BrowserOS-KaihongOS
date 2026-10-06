const fs = require('fs');
const path = 'entry/src/main/ets/components/ConfirmDialog.ets';
let src = fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');

// ---- 4a: imports + self-listening ----
const OLD_IMP = `import { SensitiveOperationType } from '../common/Types'`;
const NEW_IMP = `import { SensitiveOperationType } from '../common/Types'
import { EventBus, EventBusEvents } from '../infra/EventBus'`;
if (!src.includes(OLD_IMP)) { throw new Error('import anchor not found'); }
src = src.replace(OLD_IMP, NEW_IMP);

// ---- 4b: aboutToAppear listener + show override ----
const OLD_SHOW = `  show(agentId: string, operationType: SensitiveOperationType, targetUrl: string, targetElement: string): void {
    this.agentId = agentId
    this.operationType = operationType
    this.targetUrl = targetUrl
    this.targetElement = targetElement
    this.isVisible = true
  }`;
const NEW_SHOW = `  show(agentId: string, operationType: SensitiveOperationType, targetUrl: string, targetElement: string): void {
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
  }`;
if (!src.includes(OLD_SHOW)) { throw new Error('show anchor not found'); }
src = src.replace(OLD_SHOW, NEW_SHOW);

fs.writeFileSync(path, src.replace(/\n/g, '\r\n'), 'utf8');
console.log('ConfirmDialog patched');
