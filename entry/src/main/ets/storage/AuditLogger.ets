import { AuditLogEntry } from '../model/AuditLogEntry'
import { StorageManager } from './StorageManager'
import { Constants } from '../common/Constants'
import { redactSensitive } from '../common/Redact'
import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

class AuditLoggerImpl {
  private logQueue: AuditLogEntry[] = []
  private flushInterval: number = 5000
  private maxQueueSize: number = 100
  private retentionDays: number = 30
  /** P54: 惰性 flush 锚——log() 时距上次 flush 超过 flushInterval 即落盘（无常驻 timer） */
  private lastFlushAt: number = Date.now()

  log(entry: AuditLogEntry): void {
    this.logQueue.push(entry)
    const now = Date.now()
    if (this.logQueue.length >= this.maxQueueSize || (now - this.lastFlushAt) >= this.flushInterval) {
      this.flush()
    }
  }

  flush(): void {
    if (this.logQueue.length === 0) {
      return
    }
    this.lastFlushAt = Date.now()
    const date = new Date()
    const dateStr = `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`
    const logPath = `audit/${dateStr}.jsonl`

    // P54: StorageManager.save 是 TRUNC 覆盖写 — flush 前同步读旧文件合并，避免每批覆盖上一批
    let merged = ''
    try {
      const fullPath = `${StorageManager.getBasePath()}/${logPath}`
      const stat = fs.statSync(fullPath)
      const sizeNum: number = stat.size
      if (sizeNum > 0) {
        const file = fs.openSync(fullPath, fs.OpenMode.READ_ONLY)
        const buf = new ArrayBuffer(sizeNum)
        fs.readSync(file.fd, buf)
        fs.closeSync(file)
        const decoder = util.TextDecoder.create('utf-8')
        const existing = decoder.decodeWithStream(new Uint8Array(buf))
        if (existing.length > 0) {
          merged = existing.endsWith('\n') ? existing : existing + '\n'
        }
      }
    } catch (e) {
      // 读失败按空处理（宁可重复不可丢失）
    }

    // P42 (KAI-075): 审计写入统一脱敏（逐行）
    const lines = this.logQueue.map(entry => redactSensitive(entry.toLogString())).join('\n')
    this.logQueue = []

    StorageManager.save(logPath, merged + lines + '\n')
  }

  async query(agentId?: string, startTime?: number, endTime?: number, operationType?: string): Promise<AuditLogEntry[]> {
    const results: AuditLogEntry[] = []
    const files = await StorageManager.listDir('audit')

    for (const file of files) {
      const content = await StorageManager.load(`audit/${file}`)
      if (!content) {
        continue
      }
      const lines = content.split('\n')
      for (const line of lines) {
        if (!line.trim()) {
          continue
        }
        try {
          const json = JSON.parse(line) as Record<string, Object>
          const entry = AuditLogEntry.fromJSON(json)

          if (agentId && entry.agentId !== agentId) {
            continue
          }
          if (startTime && entry.timestamp < startTime) {
            continue
          }
          if (endTime && entry.timestamp > endTime) {
            continue
          }
          if (operationType && entry.operationType !== operationType) {
            continue
          }
          results.push(entry)
        } catch (e) {
          continue
        }
      }
    }
    return results
  }

  async cleanupOldLogs(): Promise<void> {
    const files = await StorageManager.listDir('audit')
    const now = Date.now()
    const retentionMs = this.retentionDays * 24 * 60 * 60 * 1000

    for (const file of files) {
      const content = await StorageManager.load(`audit/${file}`)
      if (!content) {
        continue
      }
      const lines = content.split('\n').filter(l => l.trim())
      if (lines.length === 0) {
        await StorageManager.delete(`audit/${file}`)
        continue
      }
      try {
        const firstLine = JSON.parse(lines[0]) as Record<string, Object>
        const timestamp = firstLine['timestamp'] as number
        if (now - timestamp > retentionMs) {
          await StorageManager.delete(`audit/${file}`)
        }
      } catch (e) {
        await StorageManager.delete(`audit/${file}`)
      }
    }
  }

  setFlushInterval(intervalMs: number): void {
    this.flushInterval = intervalMs
  }

  setMaxQueueSize(size: number): void {
    this.maxQueueSize = size
  }

  setRetentionDays(days: number): void {
    this.retentionDays = days
  }
}

export const AuditLogger = new AuditLoggerImpl()