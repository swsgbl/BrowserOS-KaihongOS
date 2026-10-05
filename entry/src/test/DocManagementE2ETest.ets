import { DocManagementFacade } from '../main/ets/docmanagement/DocManagementFacade'
import { DocPathResolver } from '../main/ets/docmanagement/storage/DocPathResolver'
import { DocStorageManager } from '../main/ets/docmanagement/storage/DocStorageManager'
import { DevPlanManager } from '../main/ets/docmanagement/business/DevPlanManager'
import { DevLogManager } from '../main/ets/docmanagement/business/DevLogManager'
import { ChangelogManager } from '../main/ets/docmanagement/business/ChangelogManager'
import { StatusReportGenerator } from '../main/ets/docmanagement/business/StatusReportGenerator'
import { ADRManager } from '../main/ets/docmanagement/business/ADRManager'
import { MeetingMinutesManager } from '../main/ets/docmanagement/business/MeetingMinutesManager'
import { MilestoneStatus, TaskStatus, ChangeType } from '../main/ets/docmanagement/enums/DocEnums'

interface TestResult {
  name: string
  passed: boolean
  detail: string
}

class DocManagementE2ETest {
  private results: TestResult[] = []

  private assert(name: string, condition: boolean, detail: string): void {
    this.results.push({ name: name, passed: condition, detail: detail })
  }

  async runAll(): Promise<TestResult[]> {
    this.results = []
    await this.testFacadeInitialization()
    await this.testFullDocumentFlow()
    await this.testMeetingADRWiring()
    await this.testMarkdownAndDepthConstraints()
    await this.testSDDCompatibility()
    return this.results
  }

  private async testFacadeInitialization(): Promise<void> {
    const initialized = await DocManagementFacade.initialize()
    this.assert('Facade.initialize', initialized, 'facade should initialize successfully')
    this.assert('Facade.isInitialized', DocManagementFacade.isInitialized(), 'initialized flag should be true')

    const devPlan = DocManagementFacade.getDevPlanManager()
    this.assert('getDevPlanManager', devPlan !== undefined, 'devPlan manager accessible')

    const devLog = DocManagementFacade.getDevLogManager()
    this.assert('getDevLogManager', devLog !== undefined, 'devLog manager accessible')

    const changelog = DocManagementFacade.getChangelogManager()
    this.assert('getChangelogManager', changelog !== undefined, 'changelog manager accessible')

    const status = DocManagementFacade.getStatusReportGenerator()
    this.assert('getStatusReportGenerator', status !== undefined, 'status generator accessible')

    const meeting = DocManagementFacade.getMeetingMinutesManager()
    this.assert('getMeetingMinutesManager', meeting !== undefined, 'meeting manager accessible')

    const adr = DocManagementFacade.getADRManager()
    this.assert('getADRManager', adr !== undefined, 'ADR manager accessible')
  }

  private async testFullDocumentFlow(): Promise<void> {
    const futureDate = this.getFutureDate(30)
    const msId = await DevPlanManager.createMilestone({
      name: 'E2E测试里程碑',
      description: '端到端流程测试',
      deliverables: '存储层;业务层;测试',
      plannedDate: futureDate
    })
    this.assert('E2E: createMilestone', msId.length > 0, `milestone: ${msId}`)

    await DevPlanManager.updateMilestoneStatus(msId, MilestoneStatus.IN_PROGRESS)
    const taskId = await DevPlanManager.addTask(msId, {
      sddTaskRef: 'DM-T001',
      name: 'E2E测试任务',
      assignee: 'tester',
      estimatedDays: 1,
      plannedStart: this.today(),
      plannedEnd: this.today()
    })
    this.assert('E2E: addTask', taskId.length > 0, `task: ${taskId}`)

    await DevPlanManager.updateTaskStatus(taskId, TaskStatus.COMPLETED)

    const logId = await DevLogManager.addLogEntry({
      date: this.today(),
      author: 'tester',
      workSummary: 'E2E流程测试：完成文档全流程验证',
      decisions: '流程符合预期',
      relatedTaskId: taskId
    })
    this.assert('E2E: addLogEntry', logId.length > 0, `log: ${logId}`)

    const versionCreated = await ChangelogManager.createVersion('0.2.0', this.today())
    this.assert('E2E: createVersion', versionCreated, 'version 0.2.0 should be created')

    await ChangelogManager.addChangeEntry('0.2.0', ChangeType.ADDED, 'E2E流程测试通过')

    const check = await ChangelogManager.checkReleasePrerequisites('0.2.0')
    this.assert('E2E: checkReleasePrerequisites', check !== undefined, `allMet: ${check.allMet}`)

    const reportSaved = await StatusReportGenerator.saveStatusReport(41)
    this.assert('E2E: saveStatusReport', reportSaved, 'status report should be saved')

    const planExists = await DocStorageManager.exists('dev-plan/development-plan.md')
    this.assert('E2E: development-plan.md exists', planExists, 'plan document should exist')

    const logExists = await DocStorageManager.exists('changelog/CHANGELOG.md')
    this.assert('E2E: CHANGELOG.md exists', logExists, 'changelog should exist')
  }

  private async testMeetingADRWiring(): Promise<void> {
    const meetingId = await MeetingMinutesManager.createMinutes({
      topic: 'E2E决策会议',
      time: `${this.today()} 09:00-10:00`,
      participants: ['pm'],
      discussionContent: '端到端决策提取测试',
      decisions: '测试决策提取联动',
      actionItems: [{ description: '验证联动', assignee: 'tester', dueDate: this.getFutureDate(1) }]
    })
    this.assert('E2E: createMinutes', meetingId.length > 0, `meeting: ${meetingId}`)

    const adrId = await MeetingMinutesManager.extractDecisionToADR(meetingId)
    this.assert('E2E: extractDecisionToADR', adrId.length > 0, `ADR: ${adrId}`)

    const adrList = await ADRManager.getADRList()
    this.assert('E2E: ADR list updated', adrList.length > 0, `ADR count: ${adrList.length}`)

    const adrIndexExists = await DocStorageManager.exists('adr/ADR-INDEX.md')
    this.assert('E2E: ADR-INDEX.md exists', adrIndexExists, 'ADR index should exist')
  }

  private async testMarkdownAndDepthConstraints(): Promise<void> {
    const paths = [
      'dev-plan/development-plan.md',
      'changelog/CHANGELOG.md',
      'adr/ADR-INDEX.md'
    ]
    for (const p of paths) {
      const depthOk = DocPathResolver.validateDepth(p)
      this.assert(`depth ok: ${p}`, depthOk, 'path should be <= 3 layers')
      const content = await DocStorageManager.load(p)
      this.assert(`markdown content: ${p}`, content !== null && content.startsWith('#'), 'content should be Markdown')
    }
  }

  private async testSDDCompatibility(): Promise<void> {
    const sddSpecExists = await DocStorageManager.exists('../browseros_kaihongos/spec.md')
    this.assert('SDD spec path check', sddSpecExists !== undefined, 'SDD check should not crash')

    const sddContent = await DocStorageManager.load('../browseros_kaihongos/spec.md')
    this.assert('SDD compatibility (no crash on traversal)', sddContent === null, 'traversal to SDD dir should be safely rejected')

    const docMgmtSpecExists = await DocStorageManager.exists('spec.md')
    this.assert('doc_management spec check no crash', docMgmtSpecExists !== undefined, 'check should not crash')
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

export const docManagementE2ETest = new DocManagementE2ETest()