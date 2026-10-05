import { AuditLogEntry } from '../model/AuditLogEntry'
import { StorageManager } from './StorageManager'
import { Constants } from '../common/Constants'

class AuditLoggerImpl {
  private logQueue: AuditLogEntry[] = []
  private flushInterval: number = 5000
  private maxQueueSize: number = 100
  private retentionDays: number = 30

  log(entry: AuditLogEntry): void {
    this.logQueue.push(entry)
    if (this.logQueue.length >= this.maxQueueSize) {
      this.flush()
    }
  }

  flush(): void {
    if (this.logQueue.length === 0) {
      return
    }
    const date = new Date()
    const dateStr = `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`
    const logPath = `audit/${dateStr}.jsonl`

    const lines = this.logQueue.map(entry => entry.toLogString()).join('\n')
    this.logQueue = []

    StorageManager.save(logPath, lines)
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