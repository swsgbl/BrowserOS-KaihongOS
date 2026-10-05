import { Milestone, Task, MilestoneStatus, TaskStatus, TimelineItem, ResourceAllocation } from '../models/DocModels'
import { MilestoneData, TaskData } from '../models/DocDataTypes'
import { DocType } from '../enums/DocEnums'
import { DocStorageManager } from '../storage/DocStorageManager'
import { DocPathResolver } from '../storage/DocPathResolver'
import { DocTemplateManager } from '../support/DocTemplateManager'
import { DocErrorCodes } from '../common/DocErrorCodes'
import { ErrorHandler, AppError } from '../../infra/ErrorHandler'
import { EventBus, EventBusEvents } from '../../infra/EventBus'

const MAX_NAME_LENGTH: number = 30
const MAX_DESC_LENGTH: number = 200
const MAX_TASK_DAYS: number = 3
const DEFAULT_AVAILABLE_DAYS: number = 15
const PLAN_DATA_FILE: string = 'plan-data.json'

class DevPlanManagerImpl {
  private milestones: Milestone[] = []
  private nextMilestoneSeq: number = 1
  private nextTaskSeq: number = 1

  private today(): string {
    const d = new Date()
    return `${d.getFullYear()}-${DocPathResolver.pad2(d.getMonth() + 1)}-${DocPathResolver.pad2(d.getDate())}`
  }

  private isValidDate(date: string): boolean {
    const regex = /^\d{4}-\d{2}-\d{2}$/
    if (!regex.test(date)) {
      return false
    }
    const parts = date.split('-')
    const y = parseInt(parts[0])
    const m = parseInt(parts[1])
    const d = parseInt(parts[2])
    if (m < 1 || m > 12 || d < 1 || d > 31) {
      return false
    }
    return true
  }

  private getMilestone(milestoneId: string): Milestone | undefined {
    for (const m of this.milestones) {
      if (m.id === milestoneId) {
        return m
      }
    }
    return undefined
  }

  private findTask(taskId: string): Task | undefined {
    for (const m of this.milestones) {
      for (const t of m.tasks) {
        if (t.id === taskId) {
          return t
        }
      }
    }
    return undefined
  }

  private canTransitionMilestone(from: MilestoneStatus, to: MilestoneStatus): boolean {
    if (from === MilestoneStatus.PLANNED) {
      return to === MilestoneStatus.IN_PROGRESS || to === MilestoneStatus.CANCELLED
    }
    if (from === MilestoneStatus.IN_PROGRESS) {
      return to === MilestoneStatus.COMPLETED || to === MilestoneStatus.DELAYED || to === MilestoneStatus.CANCELLED
    }
    if (from === MilestoneStatus.DELAYED) {
      return to === MilestoneStatus.IN_PROGRESS || to === MilestoneStatus.COMPLETED || to === MilestoneStatus.CANCELLED
    }
    return false
  }

  private canTransitionTask(from: TaskStatus, to: TaskStatus): boolean {
    if (from === TaskStatus.NOT_STARTED) {
      return to === TaskStatus.IN_PROGRESS || to === TaskStatus.BLOCKED
    }
    if (from === TaskStatus.IN_PROGRESS) {
      return to === TaskStatus.COMPLETED || to === TaskStatus.BLOCKED
    }
    if (from === TaskStatus.BLOCKED) {
      return to === TaskStatus.IN_PROGRESS || to === TaskStatus.COMPLETED
    }
    return false
  }

  async createMilestone(data: MilestoneData): Promise<string> {
    if (!data.name || data.name.length > MAX_NAME_LENGTH) {
      throw new AppError(DocErrorCodes.DEV_PLAN_001, `Milestone name exceeds ${MAX_NAME_LENGTH} chars: "${data.name}"`)
    }
    if (!data.description || data.description.length > MAX_DESC_LENGTH) {
      throw new AppError(DocErrorCodes.DEV_PLAN_002, `Milestone description exceeds ${MAX_DESC_LENGTH} chars`)
    }
    if (!this.isValidDate(data.plannedDate) || data.plannedDate < this.today()) {
      throw new AppError(DocErrorCodes.DEV_PLAN_003, `Invalid planned date: ${data.plannedDate}`)
    }
    const id = `M${DocPathResolver.pad3(this.nextMilestoneSeq)}`
    this.nextMilestoneSeq++
    const milestone: Milestone = {
      id: id,
      name: data.name,
      description: data.description,
      deliverables: data.deliverables,
      plannedDate: data.plannedDate,
      actualDate: '',
      status: MilestoneStatus.PLANNED,
      tasks: []
    }
    this.milestones.push(milestone)
    await this.savePlanDocument()
    EventBus.emit(EventBusEvents.DASHBOARD_UPDATE, { type: 'milestone_created', id: id })
    return id
  }

  async updateMilestoneStatus(milestoneId: string, status: MilestoneStatus): Promise<boolean> {
    const milestone = this.getMilestone(milestoneId)
    if (!milestone) {
      throw new AppError(DocErrorCodes.DEV_PLAN_004, `Milestone not found: ${milestoneId}`)
    }
    if (!this.canTransitionMilestone(milestone.status, status)) {
      throw new AppError(DocErrorCodes.DEV_PLAN_004, `Illegal transition: ${milestone.status} -> ${status}`)
    }
    milestone.status = status
    if (status === MilestoneStatus.COMPLETED) {
      milestone.actualDate = this.today()
    }
    EventBus.emit(EventBusEvents.DOC_MILESTONE_STATUS_CHANGE, { id: milestoneId, status: status })
    await this.savePlanDocument()
    return true
  }

  async updateMilestoneActualDate(milestoneId: string, date: string): Promise<boolean> {
    const milestone = this.getMilestone(milestoneId)
    if (!milestone) {
      throw new AppError(DocErrorCodes.DEV_PLAN_004, `Milestone not found: ${milestoneId}`)
    }
    if (!this.isValidDate(date)) {
      throw new AppError(DocErrorCodes.DEV_PLAN_003, `Invalid actual date: ${date}`)
    }
    milestone.actualDate = date
    await this.savePlanDocument()
    return true
  }

  async getMilestones(): Promise<Milestone[]> {
    return this.milestones
  }

  async getMilestoneDetail(milestoneId: string): Promise<Milestone | null> {
    const milestone = this.getMilestone(milestoneId)
    return milestone !== undefined ? milestone : null
  }

  async addTask(milestoneId: string, task: TaskData): Promise<string> {
    const milestone = this.getMilestone(milestoneId)
    if (!milestone) {
      throw new AppError(DocErrorCodes.DEV_PLAN_004, `Milestone not found: ${milestoneId}`)
    }
    if (!task.sddTaskRef || task.sddTaskRef.length === 0) {
      throw new AppError(DocErrorCodes.DEV_PLAN_005, `Task must reference SDD tasks.md entry`)
    }
    if (task.estimatedDays <= 0 || task.estimatedDays > MAX_TASK_DAYS) {
      throw new AppError(DocErrorCodes.DEV_PLAN_006, `Task granularity exceeds ${MAX_TASK_DAYS} days: ${task.estimatedDays}`)
    }
    const id = `T${DocPathResolver.pad3(this.nextTaskSeq)}`
    this.nextTaskSeq++
    const newTask: Task = {
      id: id,
      milestoneId: milestoneId,
      sddTaskRef: task.sddTaskRef,
      name: task.name,
      assignee: task.assignee,
      estimatedDays: task.estimatedDays,
      status: TaskStatus.NOT_STARTED,
      plannedStart: task.plannedStart,
      plannedEnd: task.plannedEnd
    }
    milestone.tasks.push(newTask)
    await this.savePlanDocument()
    return id
  }

  async updateTaskStatus(taskId: string, status: TaskStatus): Promise<boolean> {
    const task = this.findTask(taskId)
    if (!task) {
      throw new AppError(DocErrorCodes.DEV_PLAN_004, `Task not found: ${taskId}`)
    }
    if (!this.canTransitionTask(task.status, status)) {
      throw new AppError(DocErrorCodes.DEV_PLAN_004, `Illegal task transition: ${task.status} -> ${status}`)
    }
    task.status = status
    const milestone = this.getMilestone(task.milestoneId)
    if (milestone) {
      const allCompleted = milestone.tasks.length > 0 && milestone.tasks.every(t => t.status === TaskStatus.COMPLETED)
      if (allCompleted && milestone.status === MilestoneStatus.IN_PROGRESS) {
        milestone.status = MilestoneStatus.COMPLETED
        milestone.actualDate = this.today()
      } else if (milestone.status === MilestoneStatus.PLANNED && status === TaskStatus.IN_PROGRESS) {
        milestone.status = MilestoneStatus.IN_PROGRESS
      }
    }
    await this.savePlanDocument()
    return true
  }

  private isTimeOverlap(aStart: string, aEnd: string, bStart: string, bEnd: string): boolean {
    return aStart <= bEnd && bStart <= aEnd
  }

  async getTimelineData(): Promise<TimelineItem[]> {
    const items: TimelineItem[] = []
    for (const m of this.milestones) {
      for (const t of m.tasks) {
        let hasConflict = false
        for (const other of m.tasks) {
          if (other.id !== t.id && other.assignee === t.assignee
            && this.isTimeOverlap(t.plannedStart, t.plannedEnd, other.plannedStart, other.plannedEnd)) {
            hasConflict = true
            break
          }
        }
        const item: TimelineItem = {
          id: t.id,
          name: t.name,
          type: 'task',
          plannedStart: t.plannedStart,
          plannedEnd: t.plannedEnd,
          status: t.status,
          hasConflict: hasConflict
        }
        items.push(item)
      }
      const mItem: TimelineItem = {
        id: m.id,
        name: m.name,
        type: 'milestone',
        plannedStart: m.tasks.length > 0 ? m.tasks[0].plannedStart : m.plannedDate,
        plannedEnd: m.plannedDate,
        status: m.status,
        hasConflict: false
      }
      items.push(mItem)
    }
    return items
  }

  async getResourceAllocation(): Promise<ResourceAllocation[]> {
    const assigneeMap: Map<string, ResourceAllocation> = new Map()
    for (const m of this.milestones) {
      for (const t of m.tasks) {
        let alloc = assigneeMap.get(t.assignee)
        if (!alloc) {
          const newAlloc: ResourceAllocation = {
            assignee: t.assignee,
            tasks: [],
            totalDays: 0,
            availableDays: DEFAULT_AVAILABLE_DAYS,
            isOverloaded: false
          }
          alloc = newAlloc
          assigneeMap.set(t.assignee, alloc)
        }
        alloc.tasks.push(t.id)
        alloc.totalDays += t.estimatedDays
      }
    }
    const result: ResourceAllocation[] = []
    assigneeMap.forEach((alloc) => {
      alloc.isOverloaded = alloc.totalDays > alloc.availableDays
      result.push(alloc)
    })
    return result
  }

  private statusToText(status: MilestoneStatus): string {
    if (status === MilestoneStatus.PLANNED) {
      return '计划中'
    }
    if (status === MilestoneStatus.IN_PROGRESS) {
      return '进行中'
    }
    if (status === MilestoneStatus.COMPLETED) {
      return '已完成'
    }
    if (status === MilestoneStatus.DELAYED) {
      return '已延期'
    }
    return '已取消'
  }

  private taskStatusToText(status: TaskStatus): string {
    if (status === TaskStatus.NOT_STARTED) {
      return '未开始'
    }
    if (status === TaskStatus.IN_PROGRESS) {
      return '进行中'
    }
    if (status === TaskStatus.COMPLETED) {
      return '已完成'
    }
    return '已阻塞'
  }

  async generatePlanDocument(): Promise<string> {
    let doc = `# BrowserOS KaihongOS 开发计划\n\n## 里程碑总览\n\n`
    doc += `| 编号 | 名称 | 描述 | 目标交付物 | 计划完成日期 | 实际完成日期 | 状态 |\n`
    doc += `|------|------|------|-----------|-------------|-------------|------|\n`
    for (const m of this.milestones) {
      doc += `| ${m.id} | ${m.name} | ${m.description} | ${m.deliverables} | ${m.plannedDate} | ${m.actualDate} | ${this.statusToText(m.status)} |\n`
    }
    doc += `\n## 任务分解\n\n`
    for (const m of this.milestones) {
      doc += `### ${m.name}\n\n`
      doc += `| 任务编号 | 任务名称 | 关联SDD条目 | 负责人 | 预估工时(人日) | 计划开始 | 计划结束 | 状态 |\n`
      doc += `|---------|---------|------------|--------|--------------|---------|---------|------|\n`
      for (const t of m.tasks) {
        doc += `| ${t.id} | ${t.name} | ${t.sddTaskRef} | ${t.assignee} | ${t.estimatedDays} | ${t.plannedStart} | ${t.plannedEnd} | ${this.taskStatusToText(t.status)} |\n`
      }
      doc += `\n`
    }
    doc += `## 时间线\n\n`
    const timeline = await this.getTimelineData()
    for (const item of timeline) {
      const conflictTag = item.hasConflict ? ' [冲突]' : ''
      doc += `- ${item.id} ${item.name} (${item.type}): ${item.plannedStart} ~ ${item.plannedEnd} — ${item.status}${conflictTag}\n`
    }
    doc += `\n## 资源分配\n\n`
    doc += `| 负责人 | 任务列表 | 总工时(人日) | 可用工时(人日) | 状态 |\n`
    doc += `|--------|---------|------------|--------------|------|\n`
    const allocs = await this.getResourceAllocation()
    for (const a of allocs) {
      const statusText = a.isOverloaded ? '过载' : '正常'
      doc += `| ${a.assignee} | ${a.tasks.join(', ')} | ${a.totalDays} | ${a.availableDays} | ${statusText} |\n`
    }
    return doc
  }

  async savePlanDocument(): Promise<boolean> {
    try {
      const relativePath = DocPathResolver.resolvePath(DocType.DEV_PLAN)
      const content = await this.generatePlanDocument()
      await DocStorageManager.save(relativePath, content)
      await DocStorageManager.save(`dev-plan/${PLAN_DATA_FILE}`, JSON.stringify({
        nextMilestoneSeq: this.nextMilestoneSeq,
        nextTaskSeq: this.nextTaskSeq,
        milestones: this.milestones
      }))
      return true
    } catch (e) {
      ErrorHandler.handle(new AppError(DocErrorCodes.DEV_PLAN_004, `Save plan failed: ${e}`))
      return false
    }
  }

  async loadDataSnapshot(): Promise<void> {
    const json = await DocStorageManager.load(`dev-plan/${PLAN_DATA_FILE}`)
    if (json) {
      try {
        const parsed = JSON.parse(json) as Record<string, Object>
        this.nextMilestoneSeq = typeof parsed['nextMilestoneSeq'] === 'number' ? parsed['nextMilestoneSeq'] as number : 1
        this.nextTaskSeq = typeof parsed['nextTaskSeq'] === 'number' ? parsed['nextTaskSeq'] as number : 1
        const ms = parsed['milestones']
        if (Array.isArray(ms)) {
          this.milestones = ms as Milestone[]
        }
      } catch (e) {
      }
    }
  }
}

export const DevPlanManager = new DevPlanManagerImpl()