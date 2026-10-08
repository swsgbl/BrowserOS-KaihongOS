/**
 * P14a: 浏览历史 relationalStore(RDB) 载体
 * - 表 history(id,url,title,visit_time,visit_count) + idx_visit_time
 * - 同 URL 当日复访 visit_count+1（保留 recordNavigation 聚合语义）
 * - 清理策略: 启动异步清 90 天前 + 超 5000 条裁最旧
 * ArkTS 严格模式；API≤14（relationalStore since10，querySqlSync since12 均可用）
 */
import { relationalStore } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { HistoryEntry } from '../service/HistoryManager'

/** 保留天数（清理策略） */
const HISTORY_RETENTION_DAYS: number = 90
/** 行数上限（超限裁最旧） */
const HISTORY_MAX_ROWS: number = 5000

/** RDB 行记录（visit_count 聚合展开前的行形态） */
interface HistoryRow {
  url: string
  title: string
  visit_time: number
  visit_count: number
}

class HistoryDbImpl {
  private store: relationalStore.RdbStore | null = null
  private initPromise: Promise<boolean> | null = null

  /** EntryAbility 启动时调用；重复调用幂等（复用同一 init Promise） */
  init(context: Context): Promise<boolean> {
    if (this.initPromise !== null) {
      return this.initPromise
    }
    this.initPromise = this.doInit(context)
    return this.initPromise
  }

  isReady(): boolean {
    return this.store !== null
  }

  private async doInit(context: Context): Promise<boolean> {
    try {
      const config: relationalStore.StoreConfig = {
        name: 'history.db',
        securityLevel: relationalStore.SecurityLevel.S1
      }
      this.store = await relationalStore.getRdbStore(context, config)
      await this.store.executeSql(
        `CREATE TABLE IF NOT EXISTS history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          url TEXT NOT NULL,
          title TEXT,
          visit_time INTEGER NOT NULL,
          visit_count INTEGER DEFAULT 1
        )`)
      await this.store.executeSql(`CREATE INDEX IF NOT EXISTS idx_visit_time ON history(visit_time)`)
      console.info('[HistoryDb] init ok: history.db + idx_visit_time')
      return true
    } catch (e) {
      console.error('[HistoryDb] init failed: ' + e)
      this.store = null
      return false
    }
  }

  /**
   * 插入或当日聚合：同 URL 且 visit_time 在今天 → visit_count+1、visit_time 刷新；
   * 否则新行。返回是否成功。
   */
  async insertOrUpdate(url: string, title: string, visitTime: number): Promise<boolean> {
    const s = this.store
    if (!s) {
      return false
    }
    try {
      const dayStart = this.startOfDay(visitTime)
      const rs = await s.querySql(
        `SELECT id, visit_count FROM history WHERE url = ? AND visit_time >= ? AND visit_time < ? LIMIT 1`,
        [url, dayStart, dayStart + 86400000])
      let existingId = -1
      let existingCount = 0
      if (rs.goToNextRow()) {
        existingId = rs.getLong(rs.getColumnIndex('id'))
        existingCount = rs.getLong(rs.getColumnIndex('visit_count'))
      }
      rs.close()
      if (existingId >= 0) {
        const bucket: relationalStore.ValuesBucket = {
          'visit_count': existingCount + 1,
          'visit_time': visitTime,
          'title': title
        }
        const pred = new relationalStore.RdbPredicates('history')
        pred.equalTo('id', existingId)
        await s.update(bucket, pred)
      } else {
        const bucket: relationalStore.ValuesBucket = {
          'url': url,
          'title': title,
          'visit_time': visitTime,
          'visit_count': 1
        }
        await s.insert('history', bucket)
      }
      return true
    } catch (e) {
      console.error('[HistoryDb] insertOrUpdate failed: ' + e)
      return false
    }
  }

  /** 时间范围查询（升序 visit_time，供迁移/对账） */
  async queryRange(startTs: number, endTs: number, limit: number): Promise<HistoryRow[]> {
    const s = this.store
    if (!s) {
      return []
    }
    try {
      const rs = await s.querySql(
        `SELECT url, title, visit_time, visit_count FROM history
         WHERE visit_time >= ? AND visit_time < ? ORDER BY visit_time ASC LIMIT ?`,
        [startTs, endTs, limit])
      return this.readRows(rs)
    } catch (e) {
      console.error('[HistoryDb] queryRange failed: ' + e)
      return []
    }
  }

  /** SQL 关键词搜索（url/title LIKE，时间倒序） */
  async search(keyword: string, limit: number): Promise<HistoryRow[]> {
    const s = this.store
    if (!s || keyword.trim().length === 0) {
      return []
    }
    try {
      const kw = `%${keyword.trim()}%`
      const rs = await s.querySql(
        `SELECT url, title, visit_time, visit_count FROM history
         WHERE url LIKE ? OR title LIKE ? ORDER BY visit_time DESC LIMIT ?`,
        [kw, kw, limit])
      return this.readRows(rs)
    } catch (e) {
      console.error('[HistoryDb] search failed: ' + e)
      return []
    }
  }

  /** 最近历史（时间倒序） */
  async queryRecent(limit: number): Promise<HistoryRow[]> {
    const s = this.store
    if (!s) {
      return []
    }
    try {
      const rs = await s.querySql(
        `SELECT url, title, visit_time, visit_count FROM history
         ORDER BY visit_time DESC LIMIT ?`,
        [limit])
      return this.readRows(rs)
    } catch (e) {
      console.error('[HistoryDb] queryRecent failed: ' + e)
      return []
    }
  }

  /** 删除早于 ts 的行，返回删除行数 */
  async deleteOlderThan(ts: number): Promise<number> {
    const s = this.store
    if (!s) {
      return 0
    }
    try {
      const pred = new relationalStore.RdbPredicates('history')
      pred.lessThan('visit_time', ts)
      return await s.delete(pred)
    } catch (e) {
      console.error('[HistoryDb] deleteOlderThan failed: ' + e)
      return 0
    }
  }

  /** 清空全部 */
  async clearAll(): Promise<boolean> {
    const s = this.store
    if (!s) {
      return false
    }
    try {
      await s.executeSql('DELETE FROM history')
      return true
    } catch (e) {
      console.error('[HistoryDb] clearAll failed: ' + e)
      return false
    }
  }

  async count(): Promise<number> {
    const s = this.store
    if (!s) {
      return 0
    }
    try {
      const rs = await s.querySql('SELECT COUNT(*) AS c FROM history')
      let n = 0
      if (rs.goToNextRow()) {
        n = rs.getLong(rs.getColumnIndex('c'))
      }
      rs.close()
      return n
    } catch (e) {
      console.error('[HistoryDb] count failed: ' + e)
      return 0
    }
  }

  /**
   * 启动清理策略：保留 90 天 + 超 5000 行裁最旧（异步调用，不阻塞启动）。
   * 返回 [删除的过期行数, 裁剪行数]。
   */
  async runRetentionPolicy(): Promise<void> {
    const s = this.store
    if (!s) {
      return
    }
    try {
      const cutoff = Date.now() - HISTORY_RETENTION_DAYS * 86400000
      const expired = await this.deleteOlderThan(cutoff)
      let trimmed = 0
      const total = await this.count()
      if (total > HISTORY_MAX_ROWS) {
        // 裁掉最旧的 (total - MAX) 行：先查最旧 N 行的 visit_time 上界再删
        const excess = total - HISTORY_MAX_ROWS
        const rs = await s.querySql(
          `SELECT visit_time FROM history ORDER BY visit_time ASC LIMIT 1 OFFSET ?`, [excess - 1])
        let boundary = 0
        if (rs.goToNextRow()) {
          boundary = rs.getLong(rs.getColumnIndex('visit_time'))
        }
        rs.close()
        if (boundary > 0) {
          const pred = new relationalStore.RdbPredicates('history')
          pred.lessThan('visit_time', boundary)
          trimmed = await s.delete(pred)
        }
      }
      if (expired > 0 || trimmed > 0) {
        console.info(`[HistoryDb] retention: expired=${expired} trimmed=${trimmed} total=${await this.count()}`)
      }
    } catch (e) {
      console.error('[HistoryDb] runRetentionPolicy failed: ' + e)
    }
  }

  /** 迁移导入：旧 history.json 的全量条目（batchInsert 形态逐行 await，量级小） */
  async importLegacy(entries: HistoryEntry[]): Promise<number> {
    const s = this.store
    if (!s || entries.length === 0) {
      return 0
    }
    let n = 0
    for (const e of entries) {
      const ok = await this.insertOrUpdate(e.url, e.title, e.timestamp)
      if (ok) {
        n++
      }
    }
    console.info(`[HistoryDb] legacy imported: ${n}/${entries.length}`)
    return n
  }

  private readRows(rs: relationalStore.ResultSet): HistoryRow[] {
    const rows: HistoryRow[] = []
    try {
      const iUrl = rs.getColumnIndex('url')
      const iTitle = rs.getColumnIndex('title')
      const iTime = rs.getColumnIndex('visit_time')
      const iCount = rs.getColumnIndex('visit_count')
      while (rs.goToNextRow()) {
        rows.push({
          url: rs.getString(iUrl),
          title: rs.getString(iTitle) || '',
          visit_time: rs.getLong(iTime),
          visit_count: rs.getLong(iCount)
        })
      }
    } catch (e) {
      console.error('[HistoryDb] readRows failed: ' + e)
    } finally {
      rs.close()
    }
    return rows
  }

  private startOfDay(ts: number): number {
    const d = new Date(ts)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  }
}

export { HistoryRow }
export const HistoryDb = new HistoryDbImpl()
