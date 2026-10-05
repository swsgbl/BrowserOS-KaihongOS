import { StatusReport, RiskItem, BlockerItem, MilestoneStatusItem } from '../models/DocModels'
import { ProgressData, MilestoneProgressItem, MissingDataSource, DataConflict } from '../models/DocDataTypes'
import { MilestoneStatus, TaskStatus, RiskLevel, ProblemStatus } from '../enums/DocEnums'
import { DocStorageManager } from '../storage/DocStorageManager'
import { DocPathResolver } from '../storage/DocPathResolver'
import { DocType } from '../enums/DocEnums'
import { DocTemplateManager } from '../support/DocTemplateManager'
import { DocErrorCodes } from '../common/DocErrorCodes'
import { DevPlanManager } from './DevPlanManager'
import { DevLogManager } from './DevLogManager'
import { ChangelogManager } from './ChangelogManager'
import { ErrorHandler, AppError } from '../../infra/ErrorHandler'

const MAX_REPORT_SECONDS: number = 5

class StatusReportGeneratorImpl {
  private today(): string {
    const d = new Date()
    return `${d.getFullYear()}-${DocPathResolver.pad2(d.getMonth() + 1)}-${DocPathResolver.pad2(d.getDate())}`
  }

  private currentWeek(): number {
    const d = new Date()
    const start = new Date(d.getFullYear(), 0, 1)
    const diff = d.getTime() - start.getTime()
    const oneWeek = 7 * 24 * 60 * 60 * 1000
    return Math.ceil(diff / oneWeek)
  }

  async calculateProgress(): Promise<ProgressData> {
    const milestones = await DevPlanManager.getMilestones()
    let totalTasks = 0
    let completedTasks = 0
    const milestoneProgress: MilestoneProgressItem[] = []
    for (const m of milestones) {
      let completed = 0
      for (const t of m.tasks) {
        totalTasks++
        if (t.status === TaskStatus.COMPLETED) {
          completedTasks++
          completed++
        }
      }
      const planned = m.deliverables.split(';').filter(s => s.trim().length > 0).length
      const progress = m.tasks.length > 0 ? Math.round((completed / m.tasks.length) * 100) : 0
      const item: MilestoneProgressItem = {
        milestoneId: m.id,
        name: m.name,
        progress: progress,
        plannedDeliverables: planned > 0 ? planned : 1,
        completedDeliverables: completed
      }
      milestoneProgress.push(item)
    }
    const overall = totalTasks > 0 ? Math.round((completedTasks / totalTasks) * 100) : 0
    const result: ProgressData = {
      overallProgress: overall,
      totalTasks: totalTasks,
      completedTasks: completedTasks,
      milestoneProgress: milestoneProgress
    }
    return result
  }

  async identifyRisks(): Promise<RiskItem[]> {
    const risks: RiskItem[] = []
    const milestones = await DevPlanManager.getMilestones()
    const today = this.today()
    let seq = 1
    for (const m of milestones) {
      const isDelayed = m.status === MilestoneStatus.DELAYED
        || (m.plannedDate < today && m.status !== MilestoneStatus.COMPLETED && m.status !== MilestoneStatus.CANCELLED)
      if (isDelayed) {
        const risk: RiskItem = {
          id: `RISK-${DocPathResolver.pad3(seq)}`,
          description: `里程碑延期: ${m.id} ${m.name}（计划 ${m.plannedDate}）`,
          level: RiskLevel.HIGH,
          impact: '影响后续里程碑与版本发布',
          source: 'dev-plan'
        }
        risks.push(risk)
        seq++
      }
    }
    const longStanding = await DevLogManager.getLongStandingProblems()
    for (const p of longStanding) {
      const risk: RiskItem = {
        id: `RISK-${DocPathResolver.pad3(seq)}`,
        description: `技术问题超过5个工作日未解决: [${p.id}] ${p.description}`,
        level: RiskLevel.MEDIUM,
        impact: '阻塞相关任务推进',
        source: 'dev-log'
      }
      risks.push(risk)
      seq++
    }
    const allocations = await DevPlanManager.getResourceAllocation()
    for (const a of allocations) {
      if (a.isOverloaded) {
        const risk: RiskItem = {
          id: `RISK-${DocPathResolver.pad3(seq)}`,
          description: `人员过载: ${a.assignee}（${a.totalDays}/${a.availableDays} 人日）`,
          level: RiskLevel.MEDIUM,
          impact: '任务质量与进度风险',
          source: 'dev-plan'
        }
        risks.push(risk)
        seq++
      }
    }
    return risks
  }

  async identifyBlockers(): Promise<BlockerItem[]> {
    const blockers: BlockerItem[] = []
    const milestones = await DevPlanManager.getMilestones()
    let seq = 1
    for (const m of milestones) {
      for (const t of m.tasks) {
        if (t.status === TaskStatus.BLOCKED) {
          const blocker: BlockerItem = {
            id: `BLK-${DocPathResolver.pad3(seq)}`,
            description: `任务阻塞: ${t.id} ${t.name}（负责人 ${t.assignee}）`,
            resolver: t.assignee,
            expectedResolveDate: t.plannedEnd
          }
          blockers.push(blocker)
          seq++
        }
      }
    }
    return blockers
  }

  async detectMissingDataSources(): Promise<MissingDataSource[]> {
    const missing: MissingDataSource[] = []
    const planExists = await DocStorageManager.exists('dev-plan/development-plan.md')
    if (!planExists) {
      const item: MissingDataSource = {
        sourceName: '开发计划',
        filePath: 'dev-plan/development-plan.md',
        impact: '状态报告无法计算进度'
      }
      missing.push(item)
    }
    const changelogExists = await DocStorageManager.exists('changelog/CHANGELOG.md')
    if (!changelogExists) {
      const item: MissingDataSource = {
        sourceName: '变更日志',
        filePath: 'changelog/CHANGELOG.md',
        impact: '状态报告无法反映版本状态'
      }
      missing.push(item)
    }
    return missing
  }

  async detectDataConflicts(): Promise<DataConflict[]> {
    const conflicts: DataConflict[] = []
    const milestones = await DevPlanManager.getMilestones()
    const today = this.today()
    for (const m of milestones) {
      if (m.status === MilestoneStatus.COMPLETED && m.actualDate === '') {
        conflicts.push({
          source1: 'dev-plan',
          source2: 'dev-log',
          description: `里程碑 ${m.id} 标记已完成但无实际完成日期`,
          value1: 'COMPLETED',
          value2: '无 actualDate'
        })
      }
      if (m.status === MilestoneStatus.IN_PROGRESS && m.plannedDate < today) {
        conflicts.push({
          source1: 'dev-plan',
          source2: 'status-report',
          description: `里程碑 ${m.id} 标记进行中但计划日期已过`,
          value1: 'IN_PROGRESS',
          value2: `plannedDate=${m.plannedDate} < today=${today}`
        })
      }
      for (const t of m.tasks) {
        if (t.status === TaskStatus.COMPLETED && t.plannedEnd < today) {
          continue
        }
        if (t.status === TaskStatus.BLOCKED && t.plannedEnd < today) {
          conflicts.push({
            source1: 'dev-plan',
            source2: 'dev-log',
            description: `任务 ${t.id} 标记阻塞但计划结束日期已过`,
            value1: 'BLOCKED',
            value2: `plannedEnd=${t.plannedEnd} < today=${today}`
          })
        }
      }
    }
    const changelog = await ChangelogManager.getChangelog()
    for (const c of changelog) {
      if (c.releaseDate && c.releaseDate > today) {
        conflicts.push({
          source1: 'changelog',
          source2: 'dev-plan',
          description: `版本 ${c.version} 发布日期晚于当前日期`,
          value1: `releaseDate=${c.releaseDate}`,
          value2: `today=${today}`
        })
      }
    }
    return conflicts
  }

  async generateWeeklyReport(weekNumber: number): Promise<string> {
    const startTime = Date.now()
    const progress = await this.calculateProgress()
    const risks = await this.identifyRisks()
    const blockers = await this.identifyBlockers()
    const milestones = await DevPlanManager.getMilestones()

    const currentMilestone = milestones.length > 0 ? milestones[milestones.length - 1] : null
    let currentMilestoneText = '无'
    if (currentMilestone) {
      const statusText = currentMilestone.status === MilestoneStatus.IN_PROGRESS ? '进行中'
        : currentMilestone.status === MilestoneStatus.COMPLETED ? '已完成'
        : currentMilestone.status === MilestoneStatus.DELAYED ? '已延期'
        : currentMilestone.status === MilestoneStatus.CANCELLED ? '已取消' : '计划中'
      currentMilestoneText = `${currentMilestone.name} (${statusText})`
    }

    let doc = `# 项目状态报告 - ${new Date().getFullYear()}年第${weekNumber}周\n\n`
    doc += `## 整体进度\n- 项目整体进度: ${progress.overallProgress}%\n`
    doc += `- 当前里程碑: ${currentMilestoneText}\n\n`

    doc += `## 里程碑状态\n\n| 里程碑 | 计划完成日期 | 实际完成日期 | 状态 |\n|--------|-------------|-------------|------|\n`
    for (const m of milestones) {
      doc += `| ${m.name} | ${m.plannedDate} | ${m.actualDate} | ${m.status} |\n`
    }
    doc += `\n`

    doc += `## 风险项\n\n| 风险描述 | 风险等级 | 影响范围 |\n|---------|---------|---------|\n`
    if (risks.length === 0) {
      doc += `| 无 | - | - |\n`
    } else {
      for (const r of risks) {
        doc += `| ${r.description} | ${r.level} | ${r.impact} |\n`
      }
    }
    doc += `\n`

    doc += `## 阻塞项\n\n| 阻塞描述 | 解决人 | 期望解决时间 |\n|---------|--------|------------|\n`
    if (blockers.length === 0) {
      doc += `| 无 | - | - |\n`
    } else {
      for (const b of blockers) {
        doc += `| ${b.description} | ${b.resolver} | ${b.expectedResolveDate} |\n`
      }
    }
    doc += `\n`

    doc += `## 本周完成\n`
    const changelog = await ChangelogManager.getChangelog()
    if (changelog.length === 0) {
      doc += `- 无\n`
    } else {
      for (const c of changelog) {
        doc += `- [${c.type}] ${c.description}\n`
      }
    }
    doc += `\n## 下周计划\n- 见开发计划时间线\n`

    const elapsed = Date.now() - startTime
    if (elapsed > MAX_REPORT_SECONDS * 1000) {
      console.warn(`Status report generation took ${elapsed}ms, exceeds ${MAX_REPORT_SECONDS}s target`)
    }
    return doc
  }

  async saveStatusReport(weekNumber: number): Promise<boolean> {
    try {
      const relativePath = DocPathResolver.resolvePath(DocType.STATUS_REPORT, { year: new Date().getFullYear(), week: weekNumber })
      const content = await this.generateWeeklyReport(weekNumber)
      await DocStorageManager.save(relativePath, content)
      return true
    } catch (e) {
      ErrorHandler.handle(new AppError(DocErrorCodes.STATUS_003, `Save status report failed: ${e}`))
      return false
    }
  }
}

export const StatusReportGenerator = new StatusReportGeneratorImpl()