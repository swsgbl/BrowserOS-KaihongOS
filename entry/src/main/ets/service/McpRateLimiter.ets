/**
 * P43b (KAI-047 / 任务书 C 节): MCP 传输层每连接请求限流——滑动窗口。
 *
 * - 粒度：每 TCP 连接（HTTP keep-alive = 同一 clientId 共享预算；WS 连接同理）
 * - 默认 30 req / 10s（Constants.MCP_RATE_LIMIT_*；可经 configure() 覆盖，
 *   预留 config mcpRateLimit {max, windowMs} 运行时配置入口）
 * - 超限判定只占用 O(1) 摊销时间：命中时间戳数组按升序淘汰窗口外记录
 * - HTTP 传输超限响应：429 + JSON-RPC error -32000 "rate limited"（HttpMcpTransport）
 * - WS 传输超限响应：text 帧 JSON-RPC error -32000（WsMcpTransport）
 * - 连接关闭时 reset() 释放记录（两传输层 cleanup 路径均已接线）
 */

export class McpRateLimitDecision {
  allowed: boolean = false
  retryAfterMs: number = 0
}

class McpRateLimiterImpl {
  private max: number = 30
  private windowMs: number = 10000
  private hits: Map<string, number[]> = new Map()

  configure(max: number, windowMs: number): void {
    if (max > 0 && windowMs > 0) {
      this.max = max
      this.windowMs = windowMs
      console.info(`[MCP-RATE] configured max=${max} windowMs=${windowMs}`)
    }
  }

  getMax(): number {
    return this.max
  }

  getWindowMs(): number {
    return this.windowMs
  }

  /** 记录一次请求并判定是否放行（滑动窗口内第 max+1 次起拒绝） */
  allow(key: string): McpRateLimitDecision {
    const now = Date.now()
    let arr = this.hits.get(key)
    if (!arr) {
      arr = []
      this.hits.set(key, arr)
    }
    // 淘汰滑出窗口的旧时间戳（升序，队首最旧）
    let evict = 0
    while (evict < arr.length && now - arr[evict] >= this.windowMs) {
      evict++
    }
    if (evict > 0) {
      arr = arr.slice(evict)
      this.hits.set(key, arr)
    }
    const decision = new McpRateLimitDecision()
    if (arr.length >= this.max) {
      decision.allowed = false
      decision.retryAfterMs = Math.max(1, this.windowMs - (now - arr[0]))
      return decision
    }
    arr.push(now)
    decision.allowed = true
    decision.retryAfterMs = 0
    return decision
  }

  /** 连接关闭时释放该连接的窗口记录 */
  reset(key: string): void {
    this.hits.delete(key)
  }
}

export const McpRateLimiter = new McpRateLimiterImpl()
