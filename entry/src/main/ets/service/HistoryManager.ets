import { StorageManager } from '../storage/StorageManager'
import { HistoryDb, HistoryRow } from '../storage/HistoryDb'
import { Context } from '@kit.AbilityKit'
import { EventBus, EventBusEvents } from '../infra/EventBus'

export interface HistoryEntry {
  url: string
  title: string
  timestamp: number
}

class HistoryManagerImpl {
  private navigationStacks: Map<string, HistoryEntry[]> = new Map()
  private currentIndices: Map<string, number> = new Map()
  /**
   * P14a: RDB 内存镜像（visit_count 聚合已展开），供 getAllHistory 等
   * 同步接口零改动使用；写路径 recordNavigation 落 RDB 后同步刷新镜像。
   */
  private rdbMirror: HistoryEntry[] = []

  initStack(tabId: string): void {
    if (!this.navigationStacks.has(tabId)) {
      this.navigationStacks.set(tabId, [])
      this.currentIndices.set(tabId, -1)
    }
  }

  recordNavigation(tabId: string, url: string, title: string = ''): void {
    this.initStack(tabId)
    const stack = this.navigationStacks.get(tabId)!
    const currentIndex = this.currentIndices.get(tabId)!

    if (currentIndex < stack.length - 1) {
      stack.splice(currentIndex + 1)
    }

    const entry: HistoryEntry = { url: url, title: title, timestamp: Date.now() }
    stack.push(entry)
    this.currentIndices.set(tabId, stack.length - 1)

    // P14a: 异步落 RDB（visit_count 当日聚合）+ 同步刷新内存镜像（同步读接口零改动）
    HistoryDb.insertOrUpdate(url, title, entry.timestamp).then((ok: boolean) => {
      if (!ok) {
        console.warn('[HistoryManager] rdb insertOrUpdate failed url=' + url)
      }
    })
    this.mirrorUpsert(url, entry.timestamp, title)
    // R5: 历史变更通知（新标签页计数等订阅方即时刷新）
    EventBus.emit(EventBusEvents.HISTORY_CHANGED, entry)
  }

  canGoBack(tabId: string): boolean {
    const idx = this.currentIndices.get(tabId) ?? -1
    return idx > 0
  }

  canGoForward(tabId: string): boolean {
    const stack = this.navigationStacks.get(tabId)
    const idx = this.currentIndices.get(tabId) ?? -1
    return stack !== undefined && idx < stack.length - 1
  }

  getBackUrl(tabId: string): string | null {
    const idx = this.currentIndices.get(tabId) ?? -1
    const stack = this.navigationStacks.get(tabId)
    if (stack && idx > 0) {
      this.currentIndices.set(tabId, idx - 1)
      return stack[idx - 1].url
    }
    return null
  }

  getForwardUrl(tabId: string): string | null {
    const idx = this.currentIndices.get(tabId) ?? -1
    const stack = this.navigationStacks.get(tabId)
    if (stack && idx < stack.length - 1) {
      this.currentIndices.set(tabId, idx + 1)
      return stack[idx + 1].url
    }
    return null
  }

  getCurrentUrl(tabId: string): string | null {
    const idx = this.currentIndices.get(tabId) ?? -1
    const stack = this.navigationStacks.get(tabId)
    if (stack && idx >= 0 && idx < stack.length) {
      return stack[idx].url
    }
    return null
  }

  getHistory(tabId: string): HistoryEntry[] {
    return this.navigationStacks.get(tabId) || []
  }

  /** P5: 跨 tab 汇总最近历史（时间倒序，供历史面板使用）
   * P14a: 数据源从导航栈改为 RDB 内存镜像（启动时 queryRecent 装载） */
  getAllHistory(limit: number): HistoryEntry[] {
    const all = this.rdbMirror.slice()
    if (all.length > limit) {
      return all.slice(0, limit)
    }
    return all
  }

  /** P14a: RDB 关键词搜索（url/title LIKE）。异步版供页面调用 */
  async searchHistory(keyword: string, limit: number = 200): Promise<HistoryEntry[]> {
    const rows = await HistoryDb.search(keyword, limit)
    return rows.map((r: HistoryRow): HistoryEntry => {
      return { url: r.url, title: r.title, timestamp: r.visit_time }
    })
  }

  /** P14a: RDB 时间范围查询 */
  async queryRange(startTs: number, endTs: number, limit: number = 500): Promise<HistoryEntry[]> {
    const rows = await HistoryDb.queryRange(startTs, endTs, limit)
    return rows.map((r: HistoryRow): HistoryEntry => {
      return { url: r.url, title: r.title, timestamp: r.visit_time }
    })
  }

  /** P14a: RDB 行数（自测/hilog 观察用） */
  async getRdbCount(): Promise<number> {
    return HistoryDb.count()
  }

  clearHistory(tabId: string): void {
    this.navigationStacks.delete(tabId)
    this.currentIndices.delete(tabId)
  }

  removeStack(tabId: string): void {
    this.clearHistory(tabId)
  }

  /** P14a: 清空全部浏览历史（RDB + 镜像 + tab 栈） */
  async clearAllHistory(): Promise<void> {
    await HistoryDb.clearAll()
    this.rdbMirror = []
    this.navigationStacks.clear()
    this.currentIndices.clear()
    console.info('[HistoryManager] clearAllHistory done')
  }

  /** 兼容旧调用：tab 栈不再落盘（RDB 为唯一持久层） */
  async persistHistory(): Promise<void> {
  }

  /**
   * P14a: 启动装载链（EntryAbility 调用）：
   * 1) RDB init 建表；2) 旧 tabs/history.json 一次性迁移（完成后改名 .migrated）；
   * 3) queryRecent 装载镜像；4) 异步清理策略（90 天 + 5000 行）。
   */
  async loadHistory(context?: Context): Promise<void> {
    const ctx = context ?? this.lastContext
    if (ctx) {
      this.lastContext = ctx
      const ok = await HistoryDb.init(ctx)
      if (!ok) {
        console.error('[HistoryManager] HistoryDb init failed, history persistence degraded to memory-only')
      }
    }
    await this.migrateLegacyJson()
    await this.refreshMirror()
    HistoryDb.runRetentionPolicy()
    // R5: 镜像装载完成通知（新标签页首帧计数时序修复）
    EventBus.emit(EventBusEvents.HISTORY_CHANGED, '')
  }

  private lastContext: Context | null = null

  /** 首启检测旧 tabs/history.json → 导入 RDB → 改名 history.json.migrated */
  private async migrateLegacyJson(): Promise<void> {
    try {
      const legacyPath = 'tabs/history.json'
      const exists = await StorageManager.exists(legacyPath)
      const migratedExists = await StorageManager.exists(legacyPath + '.migrated')
      if (!exists || migratedExists) {
        return
      }
      const json = await StorageManager.loadJSON(legacyPath)
      if (!json) {
        return
      }
      // 旧格式: { [tabId]: HistoryEntry[] }
      const entries: HistoryEntry[] = []
      for (const key of Object.keys(json)) {
        const stack = json[key] as HistoryEntry[]
        if (!Array.isArray(stack)) {
          continue
        }
        for (const e of stack) {
          if (e && typeof e.url === 'string') {
            entries.push({ url: e.url, title: e.title || '', timestamp: e.timestamp || 0 })
          }
        }
      }
      const n = await HistoryDb.importLegacy(entries)
      console.info(`[HistoryManager] legacy history.json migrated: ${n} entries`)
      // 改名 .migrated（旧文件留档）
      const raw = await StorageManager.load(legacyPath)
      if (raw !== null) {
        await StorageManager.save(legacyPath + '.migrated', raw)
        await StorageManager.delete(legacyPath)
      }
    } catch (e) {
      console.error('[HistoryManager] migrateLegacyJson error: ' + e)
    }
  }

  /** 从 RDB 拉最近 500 行重建镜像（聚合展开：visit_count N → N 条） */
  private async refreshMirror(): Promise<void> {
    const rows = await HistoryDb.queryRecent(500)
    const list: HistoryEntry[] = []
    for (const r of rows) {
      const n = Math.max(1, r.visit_count)
      // 聚合行展开为 N 个同 URL 记录，时间按 visit_time 递减 1ms 模拟多次访问
      for (let i = 0; i < n; i++) {
        list.push({ url: r.url, title: r.title, timestamp: r.visit_time - i })
      }
    }
    // rows 本身时间倒序；展开后同 URL 段内保持倒序，整体再排一次兜底
    list.sort((a: HistoryEntry, b: HistoryEntry): number => b.timestamp - a.timestamp)
    this.rdbMirror = list
    console.info('[HistoryManager] mirror refreshed: rows=' + rows.length + ' expanded=' + list.length)
  }

  /** recordNavigation 后同步维护镜像（当日同 URL 位移到头部，count+1） */
  private mirrorUpsert(url: string, ts: number, title: string): void {
    const dayStart = new Date(new Date(ts).getFullYear(), new Date(new Date(ts).getMonth(), new Date(ts).getDate()).getTime()).getTime()
    let updated = false
    const next: HistoryEntry[] = []
    // 先放新条目（镜像保持时间倒序，最新在前）
    next.push({ url: url, title: title, timestamp: ts })
    for (const e of this.rdbMirror) {
      if (!updated && e.url === url && e.timestamp >= dayStart) {
        // 当日已有该 URL：聚合行头部已插入，跳过旧条目
        updated = true
        continue
      }
      next.push(e)
    }
    this.rdbMirror = next
  }
}

export const HistoryManager = new HistoryManagerImpl()
