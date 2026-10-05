import { DevLogEntry, Problem, ProblemStatus } from '../models/DocModels'
import { DevLogEntryData } from '../models/DocDataTypes'
import { DocStorageManager } from '../storage/DocStorageManager'
import { DocPathResolver } from '../storage/DocPathResolver'
import { DocType } from '../enums/DocEnums'
import { DocErrorCodes } from '../common/DocErrorCodes'
import { ErrorHandler, AppError } from '../../infra/ErrorHandler'

const MAX_AUTHOR_LENGTH: number = 20
const MAX_SUMMARY_LENGTH: number = 500
const LONG_STANDING_DAYS: number = 5
const SENSITIVE_PATTERN: RegExp = /(password|secret|token|api[_-]?key|apikey|passwd)\s*[:=]/i
const LOG_DATA_FILE: string = 'log-data.json'

class DevLogManagerImpl {
  private entries: DevLogEntry[] = []
  private nextEntrySeq: number = 1
  private nextProblemSeq: number = 1

  private isValidDate(date: string): boolean {
    const regex = /^\d{4}-\d{2}-\d{2}$/
    if (!regex.test(date)) {
      return false
    }
    const parts = date.split('-')
    const m = parseInt(parts[1])
    const d = parseInt(parts[2])
    return m >= 1 && m <= 12 && d >= 1 && d <= 31
  }

  private detectSensitiveInfo(text: string): boolean {
    return SENSITIVE_PATTERN.test(text)
  }

  private isWeekday(dateStr: string): boolean {
    const parts = dateStr.split('-')
    const y = parseInt(parts[0])
    const m = parseInt(parts[1]) - 1
    const d = parseInt(parts[2])
    const date = new Date(y, m, d)
    const day = date.getDay()
    return day >= 1 && day <= 5
  }

  private addDays(dateStr: string, days: number): string {
    const parts = dateStr.split('-')
    const y = parseInt(parts[0])
    const m = parseInt(parts[1]) - 1
    const d = parseInt(parts[2])
    const date = new Date(y, m, d)
    date.setDate(date.getDate() + days)
    return `${date.getFullYear()}-${DocPathResolver.pad2(date.getMonth() + 1)}-${DocPathResolver.pad2(date.getDate())}`
  }

  async addLogEntry(entry: DevLogEntryData): Promise<string> {
    if (!this.isValidDate(entry.date)) {
      throw new AppError(DocErrorCodes.DEV_LOG_002, `Invalid date: ${entry.date}`)
    }
    if (!entry.author || entry.author.length > MAX_AUTHOR_LENGTH) {
      throw new AppError(DocErrorCodes.DEV_LOG_001, `Author required, max ${MAX_AUTHOR_LENGTH} chars`)
    }
    if (!entry.workSummary || entry.workSummary.length > MAX_SUMMARY_LENGTH) {
      throw new AppError(DocErrorCodes.DEV_LOG_001, `Work summary required, max ${MAX_SUMMARY_LENGTH} chars`)
    }
    if (this.detectSensitiveInfo(entry.workSummary) || this.detectSensitiveInfo(entry.decisions)) {
      throw new AppError(DocErrorCodes.DEV_LOG_005, 'Sensitive credential info detected in log content')
    }
    const id = `DL${DocPathResolver.pad3(this.nextEntrySeq)}`
    this.nextEntrySeq++
    const newEntry: DevLogEntry = {
      id: id,
      date: entry.date,
      author: entry.author,
      workSummary: entry.workSummary,
      problems: [],
      decisions: entry.decisions,
      relatedTaskId: entry.relatedTaskId
    }
    this.entries.push(newEntry)
    await this.saveLogDocumentByDate(entry.date)
    return id
  }

  private findEntryByProblem(problemId: string): DevLogEntry | undefined {
    for (const e of this.entries) {
      for (const p of e.problems) {
        if (p.id === problemId) {
          return e
        }
      }
    }
    return undefined
  }

  async updateProblemStatus(problemId: string, status: ProblemStatus, solution?: string): Promise<boolean> {
    const entry = this.findEntryByProblem(problemId)
    if (!entry) {
      throw new AppError(DocErrorCodes.DEV_LOG_003, `Problem not found: ${problemId}`)
    }
    for (const p of entry.problems) {
      if (p.id === problemId) {
        const canTransition =
          (p.status === ProblemStatus.NEW_FOUND && (status === ProblemStatus.IN_PROGRESS || status === ProblemStatus.CLOSED)) ||
          (p.status === ProblemStatus.IN_PROGRESS && (status === ProblemStatus.RESOLVED || status === ProblemStatus.CLOSED)) ||
          (p.status === ProblemStatus.RESOLVED && (status === ProblemStatus.CLOSED || status === ProblemStatus.IN_PROGRESS))
        if (!canTransition) {
          throw new AppError(DocErrorCodes.DEV_LOG_003, `Illegal transition: ${p.status} -> ${status}`)
        }
        if (status === ProblemStatus.RESOLVED && (!solution || solution.length === 0)) {
          throw new AppError(DocErrorCodes.DEV_LOG_003, 'Solution required when resolving a problem')
        }
        p.status = status
        if (status === ProblemStatus.RESOLVED && solution) {
          p.solution = solution
          p.resolvedDate = this.today()
        }
        await this.saveLogDocumentByDate(entry.date)
        return true
      }
    }
    return false
  }

  private today(): string {
    const d = new Date()
    return `${d.getFullYear()}-${DocPathResolver.pad2(d.getMonth() + 1)}-${DocPathResolver.pad2(d.getDate())}`
  }

  async getLogEntries(startDate: string, endDate: string): Promise<DevLogEntry[]> {
    const result: DevLogEntry[] = []
    for (const e of this.entries) {
      if (e.date >= startDate && e.date <= endDate) {
        result.push(e)
      }
    }
    return result
  }

  async getLogByDate(date: string): Promise<DevLogEntry | null> {
    for (const e of this.entries) {
      if (e.date === date) {
        return e
      }
    }
    return null
  }

  async detectMissingDates(startDate: string, endDate: string): Promise<string[]> {
    const missing: string[] = []
    let current = startDate
    while (current <= endDate) {
      if (this.isWeekday(current)) {
        const entry = await this.getLogByDate(current)
        if (entry === null) {
          missing.push(current)
        }
      }
      current = this.addDays(current, 1)
    }
    return missing
  }

  async generateMonthlyArchive(year: number, month: number): Promise<string> {
    const monthPrefix = `${year}-${DocPathResolver.pad2(month)}`
    let doc = `# 开发日志月度汇总 - ${year}年${month}月\n\n`
    const monthEntries: DevLogEntry[] = []
    for (const e of this.entries) {
      if (e.date.startsWith(monthPrefix)) {
        monthEntries.push(e)
      }
    }
    if (monthEntries.length === 0) {
      doc += `本月无日志条目。\n`
      return doc
    }
    doc += `## 概览\n\n- 日志条目数: ${monthEntries.length}\n\n`
    doc += `## 工作摘要\n\n`
    for (const e of monthEntries) {
      doc += `- **${e.date}** (${e.author}): ${e.workSummary}\n`
    }
    doc += `\n## 问题与解决\n\n`
    let problemCount = 0
    for (const e of monthEntries) {
      for (const p of e.problems) {
        problemCount++
        doc += `- **[${p.id}]** ${p.description} — ${p.status}\n`
        if (p.solution) {
          doc += `  - 解决方案: ${p.solution}\n`
        }
      }
    }
    if (problemCount === 0) {
      doc += `本月无问题记录。\n`
    }
    const archivePath = DocPathResolver.resolveArchivePath(DocType.DEV_LOG, { year: year, month: month })
    await DocStorageManager.save(archivePath, doc)
    return doc
  }

  private countWorkdays(from: string, to: string): number {
    let count = 0
    let current = from
    let guard = 0
    while (current <= to && guard < 3650) {
      if (this.isWeekday(current)) {
        count++
      }
      current = this.addDays(current, 1)
      guard++
    }
    return count
  }

  async getLongStandingProblems(): Promise<Problem[]> {
    const result: Problem[] = []
    const today = this.today()
    for (const e of this.entries) {
      for (const p of e.problems) {
        if (p.status === ProblemStatus.IN_PROGRESS) {
          const foundDate = p.foundDate || e.date
          if (this.countWorkdays(foundDate, today) > LONG_STANDING_DAYS) {
            result.push(p)
          }
        }
      }
    }
    return result
  }

  async getUnresolvedProblems(): Promise<Problem[]> {
    const result: Problem[] = []
    for (const e of this.entries) {
      for (const p of e.problems) {
        if (p.status === ProblemStatus.NEW_FOUND || p.status === ProblemStatus.IN_PROGRESS) {
          result.push(p)
        }
      }
    }
    return result
  }

  private statusToText(status: ProblemStatus): string {
    if (status === ProblemStatus.NEW_FOUND) {
      return '新发现'
    }
    if (status === ProblemStatus.IN_PROGRESS) {
      return '处理中'
    }
    if (status === ProblemStatus.RESOLVED) {
      return '已解决'
    }
    return '已关闭'
  }

  async saveLogDocumentByDate(date: string): Promise<boolean> {
    const parts = date.split('-')
    const year = parseInt(parts[0])
    const month = parseInt(parts[1])
    return this.saveLogDocument(year, month)
  }

  async saveLogDocument(year: number, month: number): Promise<boolean> {
    try {
      const relativePath = DocPathResolver.resolvePath(DocType.DEV_LOG, { year: year, month: month })
      const monthPrefix = `${year}-${DocPathResolver.pad2(month)}`
      let doc = `# 开发日志 - ${year}年${month}月\n\n`
      const monthEntries: DevLogEntry[] = []
      for (const e of this.entries) {
        if (e.date.startsWith(monthPrefix)) {
          monthEntries.push(e)
        }
      }
      for (const e of monthEntries) {
        doc += `## ${e.date} - ${e.author}\n\n`
        doc += `### 工作内容\n${e.workSummary}\n\n`
        doc += `### 问题与风险\n`
        if (e.problems.length === 0) {
          doc += `无\n`
        } else {
          for (const p of e.problems) {
            doc += `- [${p.id}] ${p.description} — 状态: ${this.statusToText(p.status)}\n`
            if (p.solution) {
              doc += `  - 解决方案: ${p.solution}\n`
            }
          }
        }
        doc += `\n### 决策与结论\n${e.decisions}\n\n`
        doc += `### 关联任务\n- ${e.relatedTaskId}\n\n`
      }
      await DocStorageManager.save(relativePath, doc)
      await DocStorageManager.save(`dev-log/${LOG_DATA_FILE}`, JSON.stringify({
        nextEntrySeq: this.nextEntrySeq,
        nextProblemSeq: this.nextProblemSeq,
        entries: this.entries
      }))
      return true
    } catch (e) {
      ErrorHandler.handle(new AppError(DocErrorCodes.DEV_LOG_004, `Save log failed: ${e}`))
      return false
    }
  }

  addProblemToEntry(entryId: string, description: string): string | null {
    for (const e of this.entries) {
      if (e.id === entryId) {
        const pid = `P${DocPathResolver.pad3(this.nextProblemSeq)}`
        this.nextProblemSeq++
        const problem: Problem = {
          id: pid,
          description: description,
          status: ProblemStatus.NEW_FOUND,
          solution: '',
          foundDate: this.today(),
          resolvedDate: ''
        }
        e.problems.push(problem)
        return pid
      }
    }
    return null
  }

  async loadDataSnapshot(): Promise<void> {
    const json = await DocStorageManager.load(`dev-log/${LOG_DATA_FILE}`)
    if (json) {
      try {
        const parsed = JSON.parse(json) as Record<string, Object>
        this.nextEntrySeq = typeof parsed['nextEntrySeq'] === 'number' ? parsed['nextEntrySeq'] as number : 1
        this.nextProblemSeq = typeof parsed['nextProblemSeq'] === 'number' ? parsed['nextProblemSeq'] as number : 1
        const es = parsed['entries']
        if (Array.isArray(es)) {
          this.entries = es as DevLogEntry[]
        }
      } catch (e) {
      }
    }
  }
}

export const DevLogManager = new DevLogManagerImpl()