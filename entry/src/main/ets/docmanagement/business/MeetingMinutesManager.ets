import { MeetingMinutes, ActionItem, ActionItemStatus } from '../models/DocModels'
import { MeetingMinutesData, ActionItemData, ADRData } from '../models/DocDataTypes'
import { DocStorageManager } from '../storage/DocStorageManager'
import { DocPathResolver } from '../storage/DocPathResolver'
import { DocType } from '../enums/DocEnums'
import { DocTemplateManager } from '../support/DocTemplateManager'
import { DocErrorCodes } from '../common/DocErrorCodes'
import { ADRManager } from './ADRManager'

import { ErrorHandler, AppError } from '../../infra/ErrorHandler'

const MAX_TOPIC_LENGTH: number = 50
const TIME_REGEX: RegExp = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}-\d{2}:\d{2}$/
const MEETING_DATA_FILE: string = 'meeting-data.json'
const SENSITIVE_PATTERN: RegExp = /(password|secret|token|api[_-]?key|apikey|passwd)\s*[:=]/i

class MeetingMinutesManagerImpl {
  private minutes: MeetingMinutes[] = []
  private nextSeq: number = 1
  private nextActionSeq: number = 1

  private today(): string {
    const d = new Date()
    return `${d.getFullYear()}-${DocPathResolver.pad2(d.getMonth() + 1)}-${DocPathResolver.pad2(d.getDate())}`
  }

  private findMinutes(meetingId: string): MeetingMinutes | undefined {
    for (const m of this.minutes) {
      if (m.id === meetingId) {
        return m
      }
    }
    return undefined
  }

  private findActionItem(actionItemId: string): { minutes: MeetingMinutes, item: ActionItem } | undefined {
    for (const m of this.minutes) {
      for (const a of m.actionItems) {
        if (a.id === actionItemId) {
          return { minutes: m, item: a }
        }
      }
    }
    return undefined
  }

  async createMinutes(data: MeetingMinutesData): Promise<string> {
    if (!data.topic || data.topic.length > MAX_TOPIC_LENGTH) {
      throw new AppError(DocErrorCodes.MEETING_001, `Topic required, max ${MAX_TOPIC_LENGTH} chars`)
    }
    if (SENSITIVE_PATTERN.test(data.topic) || SENSITIVE_PATTERN.test(data.discussionContent) || SENSITIVE_PATTERN.test(data.decisions)) {
      throw new AppError(DocErrorCodes.MEETING_001, `Meeting content contains sensitive info`)
    }
    if (!TIME_REGEX.test(data.time)) {
      throw new AppError(DocErrorCodes.MEETING_001, `Invalid time format: ${data.time} (expected YYYY-MM-DD HH:MM-HH:MM)`)
    }
    for (const item of data.actionItems) {
      if (!item.assignee || !item.dueDate) {
        throw new AppError(DocErrorCodes.MEETING_002, `Action item requires assignee and dueDate: ${item.description}`)
      }
    }
    const id = `MTG-${DocPathResolver.pad3(this.nextSeq)}`
    this.nextSeq++
    const actionItems: ActionItem[] = []
    for (const item of data.actionItems) {
      const actionId = `ACT-${DocPathResolver.pad3(this.nextActionSeq)}`
      this.nextActionSeq++
      const action: ActionItem = {
        id: actionId,
        description: item.description,
        assignee: item.assignee,
        dueDate: item.dueDate,
        status: ActionItemStatus.PENDING,
        relatedTaskId: item.relatedTaskId !== undefined ? item.relatedTaskId : ''
      }
      actionItems.push(action)
    }
    const minutes: MeetingMinutes = {
      id: id,
      topic: data.topic,
      time: data.time,
      participants: data.participants,
      discussionContent: data.discussionContent,
      decisions: data.decisions,
      actionItems: actionItems
    }
    this.minutes.push(minutes)
    const date = data.time.substring(0, 10)
    await this.saveMinutesDocument(date)
    return id
  }

  async updateActionItemStatus(actionItemId: string, status: ActionItemStatus): Promise<boolean> {
    const found = this.findActionItem(actionItemId)
    if (!found) {
      throw new AppError(DocErrorCodes.MEETING_002, `Action item not found: ${actionItemId}`)
    }
    const canTransition =
      (found.item.status === ActionItemStatus.PENDING && (status === ActionItemStatus.IN_PROGRESS || status === ActionItemStatus.COMPLETED)) ||
      (found.item.status === ActionItemStatus.IN_PROGRESS && status === ActionItemStatus.COMPLETED)
    if (!canTransition) {
      throw new AppError(DocErrorCodes.MEETING_002, `Illegal action item transition: ${found.item.status} -> ${status}`)
    }
    found.item.status = status
    const date = found.minutes.time.substring(0, 10)
    await this.saveMinutesDocument(date)
    return true
  }

  async getMinutesByDateRange(startDate: string, endDate: string): Promise<MeetingMinutes[]> {
    const result: MeetingMinutes[] = []
    for (const m of this.minutes) {
      const date = m.time.substring(0, 10)
      if (date >= startDate && date <= endDate) {
        result.push(m)
      }
    }
    return result
  }

  async getOverdueActionItems(): Promise<ActionItem[]> {
    const result: ActionItem[] = []
    const today = this.today()
    for (const m of this.minutes) {
      for (const a of m.actionItems) {
        if (a.status !== ActionItemStatus.COMPLETED && a.dueDate < today) {
          result.push(a)
        }
      }
    }
    return result
  }

  async archiveMinutes(date: string): Promise<boolean> {
    const content = await DocStorageManager.load(`meeting/meeting-${date}.md`)
    if (content === null) {
      return false
    }
    return await DocStorageManager.append(`meeting/meeting-${date}.md`, `\n\n> 归档时间: ${this.today()}\n`)
  }

  async extractDecisionToADR(meetingId: string): Promise<string> {
    const minutes = this.findMinutes(meetingId)
    if (!minutes) {
      throw new AppError(DocErrorCodes.MEETING_004, `Meeting minutes not found: ${meetingId}`)
    }
    const adrData: ADRData = {
      title: `${minutes.topic} 决策`,
      context: `来自会议纪要 ${meetingId}（${minutes.time}）\n讨论内容: ${minutes.discussionContent}`,
      decision: minutes.decisions,
      consequences: '影响范围与后续行动见会议行动项',
      sddLinks: []
    }
    const adrId = await ADRManager.createADR(adrData)
    return adrId
  }

  private statusToText(status: ActionItemStatus): string {
    if (status === ActionItemStatus.PENDING) {
      return '待执行'
    }
    if (status === ActionItemStatus.IN_PROGRESS) {
      return '进行中'
    }
    return '已完成'
  }

  async saveMinutesDocument(date: string): Promise<boolean> {
    try {
      const relativePath = DocPathResolver.resolvePath(DocType.MEETING, { date: date })
      let doc = ''
      for (const m of this.minutes) {
        if (m.time.substring(0, 10) !== date) {
          continue
        }
        const params: Record<string, Object> = {
          'topic': m.topic,
          'time': m.time,
          'participants': m.participants,
          'discussion-content': m.discussionContent,
          'decisions': m.decisions
        }
        doc += DocTemplateManager.createFromTemplate(DocType.MEETING, params)
        doc += '\n'
        doc += '## 行动项明细\n\n'
        doc += '| 行动项 | 负责人 | 截止日期 | 状态 |\n'
        doc += '|--------|--------|---------|------|\n'
        for (const a of m.actionItems) {
          doc += `| ${a.description} | ${a.assignee} | ${a.dueDate} | ${this.statusToText(a.status)} |\n`
        }
        doc += '\n'
      }
      await DocStorageManager.save(relativePath, doc)
      await DocStorageManager.save(`meeting/${MEETING_DATA_FILE}`, JSON.stringify({
        nextSeq: this.nextSeq,
        nextActionSeq: this.nextActionSeq,
        minutes: this.minutes
      }))
      return true
    } catch (e) {
      ErrorHandler.handle(new AppError(DocErrorCodes.MEETING_004, `Save minutes failed: ${e}`))
      return false
    }
  }
  async loadDataSnapshot(): Promise<void> {
    const json = await DocStorageManager.load(`meeting/${MEETING_DATA_FILE}`)
    if (json) {
      try {
        const parsed = JSON.parse(json) as Record<string, Object>
        this.nextSeq = typeof parsed['nextSeq'] === 'number' ? parsed['nextSeq'] as number : 1
        this.nextActionSeq = typeof parsed['nextActionSeq'] === 'number' ? parsed['nextActionSeq'] as number : 1
        const ms = parsed['minutes']
        if (Array.isArray(ms)) {
          this.minutes = ms as MeetingMinutes[]
        }
      } catch (e) {
      }
    }
  }
}

export const MeetingMinutesManager = new MeetingMinutesManagerImpl()