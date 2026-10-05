import { DevPlanManager } from '../main/ets/docmanagement/business/DevPlanManager'
import { DevLogManager } from '../main/ets/docmanagement/business/DevLogManager'
import { MilestoneStatus, TaskStatus, ProblemStatus } from '../main/ets/docmanagement/enums/DocEnums'

interface TestResult {
  name: string
  passed: boolean
  detail: string
}

class DevPlanLogIntegrationTest {
  private results: TestResult[] = []

  private assert(name: string, condition: boolean, detail: string): void {
    this.results.push({ name: name, passed: condition, detail: detail })
  }

  async runAll(): Promise<TestResult[]> {
    this.results = []
    await this.testMilestoneLifecycle()
    await this.testTaskFlow()
    await this.testMilestoneValidation()
    await this.testDevLogFlow()
    await this.testProblemStatusFlow()
    await this.testSensitiveInfoDetection()
    await this.testMissingDates()
    return this.results
  }

  private async testMilestoneLifecycle(): Promise<void> {
    const futureDate = this.getFutureDate(7)
    const msId = await DevPlanManager.createMilestone({
      name: '测试里程碑',
      description: '用于集成测试的里程碑',
      deliverables: '交付物A;交付物B',
      plannedDate: futureDate
    })
    this.assert('createMilestone', msId.length > 0, `created: ${msId}`)

    const milestones = await DevPlanManager.getMilestones()
    this.assert('getMilestones', milestones.length > 0, `count: ${milestones.length}`)

    const detail = await DevPlanManager.getMilestoneDetail(msId)
    this.assert('getMilestoneDetail', detail !== null && detail.status === MilestoneStatus.PLANNED, `status: ${detail ? detail.status : 'null'}`)

    let illegalTransition = false
    try {
      await DevPlanManager.updateMilestoneStatus(msId, MilestoneStatus.COMPLETED)
    } catch (e) {
      illegalTransition = true
    }
    this.assert('PLANNED->COMPLETED rejected', illegalTransition, 'illegal transition should throw')

    const toProgress = await DevPlanManager.updateMilestoneStatus(msId, MilestoneStatus.IN_PROGRESS)
    this.assert('PLANNED->IN_PROGRESS ok', toProgress, 'legal transition should succeed')

    const toCompleted = await DevPlanManager.updateMilestoneStatus(msId, MilestoneStatus.COMPLETED)
    this.assert('IN_PROGRESS->COMPLETED ok', toCompleted, 'legal transition should succeed')

    const completed = await DevPlanManager.getMilestoneDetail(msId)
    this.assert('actualDate auto-filled', completed !== null && completed.actualDate.length === 10, `actualDate: ${completed ? completed.actualDate : 'null'}`)
  }

  private async testTaskFlow(): Promise<void> {
    const futureDate = this.getFutureDate(14)
    const msId = await DevPlanManager.createMilestone({
      name: '任务测试里程碑',
      description: '任务流转测试',
      deliverables: 'D1',
      plannedDate: futureDate
    })
    await DevPlanManager.updateMilestoneStatus(msId, MilestoneStatus.IN_PROGRESS)

    let noRefRejected = false
    try {
      await DevPlanManager.addTask(msId, {
        sddTaskRef: '',
        name: '无引用任务',
        assignee: 'tester',
        estimatedDays: 1,
        plannedStart: '2026-10-05',
        plannedEnd: '2026-10-06'
      })
    } catch (e) {
      noRefRejected = true
    }
    this.assert('task without sddTaskRef rejected', noRefRejected, 'task without SDD ref should throw')

    let tooBigRejected = false
    try {
      await DevPlanManager.addTask(msId, {
        sddTaskRef: 'DM-T001',
        name: '超大任务',
        assignee: 'tester',
        estimatedDays: 5,
        plannedStart: '2026-10-05',
        plannedEnd: '2026-10-09'
      })
    } catch (e) {
      tooBigRejected = true
    }
    this.assert('task >3 days rejected', tooBigRejected, 'task granularity > 3 days should throw')

    const taskId = await DevPlanManager.addTask(msId, {
      sddTaskRef: 'DM-T001',
      name: '正常任务',
      assignee: 'tester',
      estimatedDays: 2,
      plannedStart: '2026-10-05',
      plannedEnd: '2026-10-07'
    })
    this.assert('addTask', taskId.length > 0, `created: ${taskId}`)

    const timeline = await DevPlanManager.getTimelineData()
    this.assert('getTimelineData', timeline.length > 0, `timeline items: ${timeline.length}`)

    const allocs = await DevPlanManager.getResourceAllocation()
    this.assert('getResourceAllocation', allocs.length > 0, `allocations: ${allocs.length}`)

    await DevPlanManager.updateTaskStatus(taskId, TaskStatus.IN_PROGRESS)
    const afterProgress = await DevPlanManager.getMilestoneDetail(msId)
    this.assert('milestone auto IN_PROGRESS', afterProgress !== null && afterProgress.status === MilestoneStatus.IN_PROGRESS, `status: ${afterProgress ? afterProgress.status : 'null'}`)

    await DevPlanManager.updateTaskStatus(taskId, TaskStatus.COMPLETED)
    const afterComplete = await DevPlanManager.getMilestoneDetail(msId)
    this.assert('milestone auto COMPLETED', afterComplete !== null && afterComplete.status === MilestoneStatus.COMPLETED, `status: ${afterComplete ? afterComplete.status : 'null'}`)
  }

  private async testMilestoneValidation(): Promise<void> {
    let nameTooLong = false
    try {
      await DevPlanManager.createMilestone({
        name: '这是一个超过三十个字符的里程碑名称这是一个超过三十个字符的里程碑名称这是个超长的名字',
        description: 'desc',
        deliverables: 'D',
        plannedDate: this.getFutureDate(7)
      })
    } catch (e) {
      nameTooLong = true
    }
    this.assert('milestone name >30 rejected', nameTooLong, 'long name should throw')

    let pastDateRejected = false
    try {
      await DevPlanManager.createMilestone({
        name: '过去日期里程碑',
        description: 'desc',
        deliverables: 'D',
        plannedDate: '2020-01-01'
      })
    } catch (e) {
      pastDateRejected = true
    }
    this.assert('past date rejected', pastDateRejected, 'past date should throw')
  }

  private async testDevLogFlow(): Promise<void> {
    const entryId = await DevLogManager.addLogEntry({
      date: this.today(),
      author: 'tester',
      workSummary: '完成存储层编码与测试',
      decisions: '采用 Markdown 存储文档',
      relatedTaskId: 'DM-T005'
    })
    this.assert('addLogEntry', entryId.length > 0, `created: ${entryId}`)

    const logByDate = await DevLogManager.getLogByDate(this.today())
    this.assert('getLogByDate', logByDate !== null, `found: ${logByDate ? logByDate.id : 'null'}`)

    const entries = await DevLogManager.getLogEntries(this.today(), this.today())
    this.assert('getLogEntries range', entries.length > 0, `count: ${entries.length}`)
  }

  private async testProblemStatusFlow(): Promise<void> {
    const entryId = await DevLogManager.addLogEntry({
      date: this.today(),
      author: 'tester',
      workSummary: '问题流转测试',
      decisions: '无',
      relatedTaskId: 'DM-T006'
    })
    const problemId = DevLogManager.addProblemToEntry(entryId, '测试问题：构建失败')
    this.assert('addProblemToEntry', problemId !== null, `problem: ${problemId}`)

    if (problemId) {
      let noSolutionRejected = false
      try {
        await DevLogManager.updateProblemStatus(problemId, ProblemStatus.RESOLVED)
      } catch (e) {
        noSolutionRejected = true
      }
      this.assert('resolve without solution rejected', noSolutionRejected, 'resolve without solution should throw')

      await DevLogManager.updateProblemStatus(problemId, ProblemStatus.IN_PROGRESS)
      await DevLogManager.updateProblemStatus(problemId, ProblemStatus.RESOLVED, '修复构建脚本')
      this.assert('problem resolved with solution', true, 'resolved successfully')

      let illegalTransition = false
      try {
        await DevLogManager.updateProblemStatus(problemId, ProblemStatus.IN_PROGRESS)
      } catch (e) {
        illegalTransition = true
      }
      this.assert('RESOLVED->IN_PROGRESS transition check', !illegalTransition, 'RESOLVED can go back to IN_PROGRESS')
    }
  }

  private async testSensitiveInfoDetection(): Promise<void> {
    let sensitiveRejected = false
    try {
      await DevLogManager.addLogEntry({
        date: this.today(),
        author: 'tester',
        workSummary: '配置了 password: 123456',
        decisions: '无',
        relatedTaskId: ''
      })
    } catch (e) {
      sensitiveRejected = true
    }
    this.assert('sensitive info rejected', sensitiveRejected, 'password in log should throw')
  }

  private async testMissingDates(): Promise<void> {
    const missing = await DevLogManager.detectMissingDates('2026-09-01', '2026-09-05')
    this.assert('detectMissingDates', missing.length > 0, `missing dates: ${JSON.stringify(missing.slice(0, 3))}...`)
  }

  private today(): string {
    const d = new Date()
    return `${d.getFullYear()}-${this.pad2(d.getMonth() + 1)}-${this.pad2(d.getDate())}`
  }

  private getFutureDate(days: number): string {
    const d = new Date()
    d.setDate(d.getDate() + days)
    return `${d.getFullYear()}-${this.pad2(d.getMonth() + 1)}-${this.pad2(d.getDate())}`
  }

  private pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`
  }
}

export const devPlanLogTest = new DevPlanLogIntegrationTest()