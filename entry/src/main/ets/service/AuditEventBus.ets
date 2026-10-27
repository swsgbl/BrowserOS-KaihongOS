import { AuditLogEntry } from '../model/AuditLogEntry'
import { AuditLogger } from '../storage/AuditLogger'
import { redactSensitive } from '../common/Redact'

/**
 * P54: 统一审计事件总线 —— 把内部 Agent 执行与外部 MCP 工具调用的关键操作
 * 收敛到单一事件流（内存 200 条环形缓冲 + 落盘 AuditLogger 既有 audit/*.jsonl 队列）。
 *
 * 设计要点：
 * - 事件模型 AuditEvent：sessionId（内部操作固定 'internal-agent'，外部 MCP 用真实会话 id）、
 *   tabId、eventType（tool_start|tool_end|navigation|tab_created|tab_closed|screenshot|session_status）、
 *   toolName、status、durationMs、redactedInput/redactedOutput、errorCode。
 * - 脱敏：写入前统一 redactSensitive（浅层）+ 截断（512 字符），保证落盘内容可展示。
 * - 环形缓冲：List 200 条（新事件 push 尾部，超限 shift 头部），AuditPage 倒序渲染最近 200 条。
 * - 落盘：转 AuditLogEntry 走既有 AuditLogger（队列 100/5s flush、30 天保留、逐行 redact），
 *   不引入新持久化路径。
 * - ArkTS 严格模式：显式类、Map/Array 显式类型、禁索引签名（用 Map）。
 */

/** 内部 Agent 操作的统一 sessionId（区别于外部 MCP 会话） */
export const AUDIT_INTERNAL_SESSION: string = 'internal-agent'

/** 环形缓冲上限（简报：最近 200 条） */
const RING_CAPACITY: number = 200

/** 单字段脱敏后最大长度 */
const FIELD_MAX_LEN: number = 512

export class AuditEvent {
  sessionId: string = ''
  tabId: string = ''
  eventType: string = ''
  toolName: string = ''
  status: string = ''
  durationMs: number = 0
  redactedInput: string = ''
  redactedOutput: string = ''
  errorCode: string = ''
  timestamp: number = 0
  /** 自增序号（AuditPage ForEach key 稳定性） */
  seq: number = 0

  constructor() {
  }
}

/** 事件类型枚举（ArkTS 无 string enum 联合，用常量类） */
export class AuditEventType {
  static readonly TOOL_START: string = 'tool_start'
  static readonly TOOL_END: string = 'tool_end'
  static readonly NAVIGATION: string = 'navigation'
  static readonly TAB_CREATED: string = 'tab_created'
  static readonly TAB_CLOSED: string = 'tab_closed'
  static readonly SCREENSHOT: string = 'screenshot'
  static readonly SESSION_STATUS: string = 'session_status'
}

class AuditEventBusImpl {
  private ring: AuditEvent[] = []
  private seqCounter: number = 0
  private listeners: Array<(e: AuditEvent) => void> = []

  /** 单字段脱敏 + 截断 */
  private sanitize(v: string | null | undefined): string {
    if (v === null || v === undefined) {
      return ''
    }
    let s = `${v}`
    try {
      s = redactSensitive(s)
    } catch (e) {
      // redact 失败保底：至少截断
    }
    if (s.length > FIELD_MAX_LEN) {
      s = s.substring(0, FIELD_MAX_LEN) + '…'
    }
    return s
  }

  /**
   * 核心记录入口。所有接线点统一走这里；内部 Agent 调用方传
   * sessionId=AUDIT_INTERNAL_SESSION（或省略，默认内部）。
   */
  record(sessionId: string, tabId: string, eventType: string, toolName: string,
    status: string, durationMs: number, input: string, output: string, errorCode: string): AuditEvent {
    const ev = new AuditEvent()
    ev.sessionId = sessionId.length > 0 ? sessionId : AUDIT_INTERNAL_SESSION
    ev.tabId = tabId
    ev.eventType = eventType
    ev.toolName = toolName
    ev.status = status
    ev.durationMs = durationMs
    ev.redactedInput = this.sanitize(input)
    ev.redactedOutput = this.sanitize(output)
    ev.errorCode = errorCode
    ev.timestamp = Date.now()
    this.seqCounter++
    ev.seq = this.seqCounter

    // 环形缓冲（push 尾、超限 shift 头）
    this.ring.push(ev)
    while (this.ring.length > RING_CAPACITY) {
      this.ring.shift()
    }

    // 落盘：转既有 AuditLogEntry（operationType = eventType:toolName 便于既有 query 过滤）
    const entry = new AuditLogEntry(`audit_${ev.seq}`, ev.sessionId,
      `${ev.eventType}${ev.toolName.length > 0 ? ':' + ev.toolName : ''}`, ev.tabId)
    entry.setResult(ev.status, ev.errorCode, ev.durationMs)
    entry.paramsRedacted = ev.redactedInput
    try {
      AuditLogger.log(entry)
    } catch (e) {
      // 落盘失败不影响内存事件流
    }

    // 通知订阅者（AuditPage 刷新用）
    const snapshot = this.copyEvent(ev)
    for (const fn of this.listeners) {
      try {
        fn(snapshot)
      } catch (e) {
        console.error(`[AuditEventBus] listener error: ${e}`)
      }
    }
    return ev
  }

  /** 内部 Agent 便捷入口 */
  recordInternal(tabId: string, eventType: string, toolName: string, status: string,
    durationMs: number, input: string, output: string, errorCode: string): AuditEvent {
    return this.record(AUDIT_INTERNAL_SESSION, tabId, eventType, toolName, status,
      durationMs, input, output, errorCode)
  }

  /** 最近事件（倒序 = 最新在前），AuditPage 直接渲染 */
  getRecent(limit: number = RING_CAPACITY): AuditEvent[] {
    const out: AuditEvent[] = []
    const n = this.ring.length
    const take = Math.min(limit, n)
    for (let i = n - 1; i >= n - take; i--) {
      out.push(this.copyEvent(this.ring[i]))
    }
    return out
  }

  /** 订阅新事件（页面刷新）。返回取消函数 */
  subscribe(fn: (e: AuditEvent) => void): () => void {
    this.listeners.push(fn)
    return () => {
      const idx = this.listeners.indexOf(fn)
      if (idx >= 0) {
        this.listeners.splice(idx, 1)
      }
    }
  }

  private copyEvent(src: AuditEvent): AuditEvent {
    const ev = new AuditEvent()
    ev.sessionId = src.sessionId
    ev.tabId = src.tabId
    ev.eventType = src.eventType
    ev.toolName = src.toolName
    ev.status = src.status
    ev.durationMs = src.durationMs
    ev.redactedInput = src.redactedInput
    ev.redactedOutput = src.redactedOutput
    ev.errorCode = src.errorCode
    ev.timestamp = src.timestamp
    ev.seq = src.seq
    return ev
  }
}

export const AuditEventBus = new AuditEventBusImpl()
