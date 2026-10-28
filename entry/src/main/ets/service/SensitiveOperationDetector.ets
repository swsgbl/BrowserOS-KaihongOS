import { SensitiveOperationType } from '../common/Types'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ConfigManager } from '../storage/ConfigManager'

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

    // P63: FORM_SUBMIT 字面量档已移除（Zodex 裁决）——'form'/'submit' 子串匹配可绕过（#su vs input[type=submit]）、
    // 打断搜索提交这类常规 agent 流、上游 BrowserOS 无工具级确认档。PAYMENT/DELETE/SETTINGS 关键词层保留。
    return null
  }

  /** P42 (KAI-074): type 工具输入检测——selector 与 text 合并走敏感词表（password/payment/删除/设置类） */
  detectType(agentId: string, selector: string, text: string): SensitiveOperationType | null {
    // selector 权重同 click；text 单独再扫一遍（输入内容含敏感词也算）
    const clickLike = this.detectClick(agentId, selector, text)
    if (clickLike) {
      return clickLike
    }
    return this.detectNavigation(agentId, text)
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

  requestConfirmation(agentId: string, operationType: SensitiveOperationType,
    targetUrl: string, targetElement: string): Promise<boolean> {
    return new Promise(resolve => {
      // p10b: sensitiveConfirm=false 时自动放行 —— 不弹 ConfirmDialog、MCP tools/call 不挂起直接执行（DEVPLAN P10 决策）
      if (!ConfigManager.isSensitiveConfirm()) {
        console.info('[SensitiveOp] sensitiveConfirm off -> AUTO-ALLOW ' + operationType + ' agent=' + agentId + ' url=' + targetUrl)
        resolve(true)
        return
      }
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