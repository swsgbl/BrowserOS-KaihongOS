import { SensitiveOperationType } from '../common/Types'
import { EventBus, EventBusEvents } from '../infra/EventBus'

interface SensitiveOperationRequest {
  agentId: string
  operationType: SensitiveOperationType
  targetUrl: string
  targetElement: string
  timestamp: number
  resolve: (confirmed: boolean) => void
}

interface SensitiveOperationEventData {
  agentId: string
  operationType: SensitiveOperationType
  targetUrl: string
  targetElement: string
  timestamp: number
}

interface SensitiveOperationConfirmData {
  agentId: string
  operationType: SensitiveOperationType
}

class SensitiveOperationDetectorImpl {
  private sensitiveKeywords: Record<SensitiveOperationType, string[]> = {
    [SensitiveOperationType.PAYMENT]: ['pay', 'checkout', 'purchase', 'buy', 'order', 'submit-payment'],
    [SensitiveOperationType.DELETE]: ['delete', 'remove', 'destroy', 'drop', 'purge'],
    [SensitiveOperationType.SETTINGS_CHANGE]: ['settings', 'security', 'password', 'account', 'admin'],
    [SensitiveOperationType.FORM_SUBMIT]: [],
    [SensitiveOperationType.UNSPECIFIED_NAVIGATION]: []
  }

  detectClick(agentId: string, selector: string, buttonText: string): SensitiveOperationType | null {
    const lowerSelector = selector.toLowerCase()
    const lowerText = buttonText.toLowerCase()

    for (const type of [SensitiveOperationType.PAYMENT, SensitiveOperationType.DELETE, SensitiveOperationType.SETTINGS_CHANGE]) {
      const keywords = this.sensitiveKeywords[type]
      for (const keyword of keywords) {
        if (lowerSelector.includes(keyword) || lowerText.includes(keyword)) {
          return type
        }
      }
    }

    if (lowerSelector.includes('form') || lowerSelector.includes('submit')) {
      return SensitiveOperationType.FORM_SUBMIT
    }

    return null
  }

  detectNavigation(agentId: string, url: string): SensitiveOperationType | null {
    const lowerUrl = url.toLowerCase()

    for (const type of [SensitiveOperationType.PAYMENT, SensitiveOperationType.DELETE, SensitiveOperationType.SETTINGS_CHANGE]) {
      const keywords = this.sensitiveKeywords[type]
      for (const keyword of keywords) {
        if (lowerUrl.includes(keyword)) {
          return type
        }
      }
    }

    return null
  }

  detectFormSubmit(agentId: string, selector: string): SensitiveOperationType | null {
    if (selector.toLowerCase().includes('form')) {
      return SensitiveOperationType.FORM_SUBMIT
    }
    return null
  }

  isSensitive(agentId: string, operation: string, target: string, extra?: string): SensitiveOperationType | null {
    const clickResult = this.detectClick(agentId, target, extra || '')
    if (clickResult) {
      return clickResult
    }

    const navResult = this.detectNavigation(agentId, target)
    if (navResult) {
      return navResult
    }

    const formResult = this.detectFormSubmit(agentId, target)
    if (formResult) {
      return formResult
    }

    return null
  }

  requestConfirmation(agentId: string, operationType: SensitiveOperationType,
    targetUrl: string, targetElement: string): Promise<boolean> {
    return new Promise(resolve => {
      const request: SensitiveOperationRequest = {
        agentId,
        operationType,
        targetUrl,
        targetElement,
        timestamp: Date.now(),
        resolve
      }

      const detectData: SensitiveOperationEventData = {
        agentId: agentId,
        operationType: operationType,
        targetUrl: targetUrl,
        targetElement: targetElement,
        timestamp: request.timestamp
      }
      EventBus.emit(EventBusEvents.SENSITIVE_OPERATION_DETECTED, detectData)

      const confirmedHandler = (data: Object) => {
        const detail = data as SensitiveOperationConfirmData
        if (detail.agentId === agentId && detail.operationType === operationType) {
          EventBus.off(EventBusEvents.SENSITIVE_OPERATION_CONFIRMED, confirmedHandler)
          EventBus.off(EventBusEvents.SENSITIVE_OPERATION_REJECTED, rejectedHandler)
          resolve(true)
        }
      }

      const rejectedHandler = (data: Object) => {
        const detail = data as SensitiveOperationConfirmData
        if (detail.agentId === agentId && detail.operationType === operationType) {
          EventBus.off(EventBusEvents.SENSITIVE_OPERATION_CONFIRMED, confirmedHandler)
          EventBus.off(EventBusEvents.SENSITIVE_OPERATION_REJECTED, rejectedHandler)
          resolve(false)
        }
      }

      EventBus.on(EventBusEvents.SENSITIVE_OPERATION_CONFIRMED, confirmedHandler)
      EventBus.on(EventBusEvents.SENSITIVE_OPERATION_REJECTED, rejectedHandler)
    })
  }

  confirmOperation(agentId: string, operationType: SensitiveOperationType): void {
    const confirmData: SensitiveOperationConfirmData = { agentId: agentId, operationType: operationType }
    EventBus.emit(EventBusEvents.SENSITIVE_OPERATION_CONFIRMED, confirmData)
  }

  rejectOperation(agentId: string, operationType: SensitiveOperationType): void {
    const rejectData: SensitiveOperationConfirmData = { agentId: agentId, operationType: operationType }
    EventBus.emit(EventBusEvents.SENSITIVE_OPERATION_REJECTED, rejectData)
  }
}

export const SensitiveOperationDetector = new SensitiveOperationDetectorImpl()