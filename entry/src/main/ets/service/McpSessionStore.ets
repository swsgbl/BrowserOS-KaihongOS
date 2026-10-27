/**
 * P51 (1a): MCP 会话存储 —— sessionId → { TTL, ownedTabIds, profile } 映射。
 *
 * 背景（外部审计 P51 方案）：
 * - 此前 MCP 工具调用统一 fallback 到全局 active tab，两个并发 agent 会互相
 *   踩对方的页面 —— 并发隔离的根因。
 * - 本 store 为会话真值源：initialize 创建 session（返回 Mcp-Session-Id），
 *   后续每个 tools/call 必须携带并解析到 session，未携带/未知/过期 → -32001。
 *
 * 设计约束（ArkTS）：Set<string> 不可序列化，ownedTabIds 用 string[] 内存保存。
 */
import { util } from '@kit.ArkTS'

/** 会话记录（ArkTS class，避开 untyped obj literal 限制） */
export class McpSession {
  sessionId: string = ''
  clientId: string = ''
  createdAt: number = 0
  lastSeen: number = 0
  expiresAt: number = 0
  ownedTabIds: string[] = []
  profileTarget: string = 'default'
}

const SESSION_TTL_MS: number = 30 * 60 * 1000  // brief: TTL 30min
const MAX_SESSIONS: number = 64                // 防表膨胀：超过时清最旧过期项

class McpSessionStoreImpl {
  private sessions: Map<string, McpSession> = new Map()

  /** initialize 成功时创建会话，返回新 sessionId */
  create(clientId: string, profileTarget: string = 'default'): McpSession {
    this.sweep()
    const s = new McpSession()
    s.sessionId = util.generateRandomUUID()
    s.clientId = clientId
    s.createdAt = Date.now()
    s.lastSeen = s.createdAt
    s.expiresAt = s.createdAt + SESSION_TTL_MS
    s.profileTarget = profileTarget
    this.sessions.set(s.sessionId, s)
    console.info(`[P51] session created id=${s.sessionId} client=${clientId} profile=${profileTarget} total=${this.sessions.size}`)
    return s
  }

  /**
   * 校验并续期。返回 null = 未知/过期（调用方应回 -32001）。
   * 命中时刷新 lastSeen 与 expiresAt（滑动窗口 TTL）。
   */
  touch(sessionId: string): McpSession | null {
    if (!sessionId) {
      return null
    }
    const s = this.sessions.get(sessionId)
    if (!s) {
      return null
    }
    const now = Date.now()
    if (now >= s.expiresAt) {
      this.sessions.delete(sessionId)
      console.warn(`[P51] session expired (rejected): ${sessionId}`)
      return null
    }
    s.lastSeen = now
    s.expiresAt = now + SESSION_TTL_MS
    return s
  }

  /** 会话是否存在（不续期，供 HTTP 层 404 判定） */
  peek(sessionId: string): McpSession | null {
    const s = this.sessions.get(sessionId)
    if (!s) {
      return null
    }
    return Date.now() < s.expiresAt ? s : null
  }

  /** tabs new：登记 tab 归属 */
  ownTab(sessionId: string, tabId: string): void {
    const s = this.sessions.get(sessionId)
    if (!s || !tabId) {
      return
    }
    if (s.ownedTabIds.indexOf(tabId) < 0) {
      s.ownedTabIds.push(tabId)
    }
  }

  /** tabs close：解除归属 */
  releaseTab(sessionId: string, tabId: string): void {
    const s = this.sessions.get(sessionId)
    if (!s) {
      return
    }
    const i = s.ownedTabIds.indexOf(tabId)
    if (i >= 0) {
      s.ownedTabIds.splice(i, 1)
    }
  }

  /** 会话拥有的 tab（首个 = 无显式 tabId 时的默认目标） */
  firstOwnedTab(sessionId: string): string {
    const s = this.sessions.get(sessionId)
    if (!s || s.ownedTabIds.length === 0) {
      return ''
    }
    return s.ownedTabIds[0]
  }

  /** 调试用快照（脱敏：不含 tab 内容） */
  stats(): Record<string, Object> {
    this.sweep()
    const owned: Record<string, Object> = {}
    this.sessions.forEach((s, k) => {
      owned[k.substring(0, 8)] = s.ownedTabIds.length as Object
    })
    return { 'total': this.sessions.size, 'owned': owned }
  }

  /** 清理过期项；仍超上限则丢最旧 */
  private sweep(): void {
    const now = Date.now()
    const dead: string[] = []
    this.sessions.forEach((s, k) => {
      if (now >= s.expiresAt) {
        dead.push(k)
      }
    })
    for (const k of dead) {
      this.sessions.delete(k)
    }
    while (this.sessions.size > MAX_SESSIONS) {
      let oldestKey = ''
      let oldestTs = Number.MAX_VALUE
      this.sessions.forEach((s, k) => {
        if (s.lastSeen < oldestTs) {
          oldestTs = s.lastSeen
          oldestKey = k
        }
      })
      if (!oldestKey) {
        break
      }
      this.sessions.delete(oldestKey)
    }
  }
}

export const McpSessionStore = new McpSessionStoreImpl()
