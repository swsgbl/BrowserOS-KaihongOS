import { MeetingMinutesManager } from '../main/ets/docmanagement/business/MeetingMinutesManager'
import { StatusReportGenerator } from '../main/ets/docmanagement/business/StatusReportGenerator'
import { ActionItemStatus } from '../main/ets/docmanagement/enums/DocEnums'

interface TestResult {
  name: string
  passed: boolean
  detail: string
}

class MeetingStatusIntegrationTest {
  private results: TestResult[] = []

  private assert(name: string, condition: boolean, detail: string): void {
    this.results.push({ name: name, passed: condition, detail: detail })
  }

  async runAll(): Promise<TestResult[]> {
    this.results = []
    await this.testMeetingFlow()
    await this.testActionItemFlow()
    await this.testDecisionExtraction()
    await this.testStatusReport()
    await this.testMissingDataSources()
    return this.results
  }

  private async testMeetingFlow(): Promise<void> {
    let noAssigneeRejected = false
    try {
      await MeetingMinutesManager.createMinutes({
        topic: '测试会议',
        time: '2026-10-05 10:00-11:00',
        participants: ['tester'],
        discussionContent: '讨论测试方案',
        decisions: '采用方案A',
        actionItems: [{ description: '无负责人行动项', assignee: '', dueDate: '2026-10-06' }]
      })
    } catch (e) {
      noAssigneeRejected = true
    }
    this.assert('action item without assignee rejected', noAssigneeRejected, 'missing assignee should throw')

    let badTimeRejected = false
    try {
      await MeetingMinutesManager.createMinutes({
        topic: '时间格式测试',
        time: '10:00-11:00',
        participants: ['tester'],
        discussionContent: '讨论',
        decisions: '无',
        actionItems: []
      })
    } catch (e) {
      badTimeRejected = true
    }
    this.assert('bad time format rejected', badTimeRejected, 'time without date should throw')

    const meetingId = await MeetingMinutesManager.createMinutes({
      topic: '集成测试会议',
      time: '2026-10-05 10:00-11:00',
      participants: ['tester', 'dev'],
      discussionContent: '讨论文档管理体系集成测试方案',
      decisions: '采用自验证测试脚本方式',
      actionItems: [
        { description: '编写集成测试', assignee: 'tester', dueDate: '2026-10-06' }
      ]
    })
    this.assert('createMinutes', meetingId.length > 0, `created: ${meetingId}`)

    const range = await MeetingMinutesManager.getMinutesByDateRange('2026-10-01', '2026-10-31')
    this.assert('getMinutesByDateRange', range.length > 0, `count: ${range.length}`)
  }

  private async testActionItemFlow(): Promise<void> {
    const meetingId = await MeetingMinutesManager.createMinutes({
      topic: '行动项测试会议',
      time: '2026-10-05 14:00-15:00',
      participants: ['tester'],
      discussionContent: '行动项状态流转测试',
      decisions: '无',
      actionItems: [
        { description: '待执行行动项', assignee: 'dev', dueDate: '2026-10-10' }
      ]
    })
    this.assert('createMinutes for action items', meetingId.length > 0, `created: ${meetingId}`)

    const minutes = await MeetingMinutesManager.getMinutesByDateRange('2026-10-05', '2026-10-05')
    let actionItemId = ''
    for (const m of minutes) {
      for (const a of m.actionItems) {
        if (a.description === '待执行行动项') {
          actionItemId = a.id
        }
      }
    }
    if (actionItemId.length > 0) {
      await MeetingMinutesManager.updateActionItemStatus(actionItemId, ActionItemStatus.IN_PROGRESS)
      await MeetingMinutesManager.updateActionItemStatus(actionItemId, ActionItemStatus.COMPLETED)
      this.assert('action item status flow', true, 'PENDING->IN_PROGRESS->COMPLETED succeeded')
    } else {
      this.assert('action item status flow', false, 'action item not found')
    }
  }

  private async testDecisionExtraction(): Promise<void> {
    const meetingId = await MeetingMinutesManager.createMinutes({
      topic: '技术决策评审会',
      time: '2026-10-05 16:00-17:00',
      participants: ['pm', 'dev'],
      discussionContent: '评审 ABC 字节码版本方案',
      decisions: '采用 --target-api-version=14 方案',
      actionItems: []
    })
    const adrId = await MeetingMinutesManager.extractDecisionToADR(meetingId)
    this.assert('extractDecisionToADR', adrId.length > 0, `ADR created: ${adrId}`)
  }

  private async testStatusReport(): Promise<void> {
    const startTime = Date.now()
    const report = await StatusReportGenerator.generateWeeklyReport(41)
    const elapsed = Date.now() - startTime
    this.assert('generateWeeklyReport', report.length > 0, `report length: ${report.length}`)
    this.assert('report contains progress', report.includes('整体进度'), 'report should contain progress section')
    this.assert('report contains risks', report.includes('风险项'), 'report should contain risks section')
    this.assert('report contains blockers', report.includes('阻塞项'), 'report should contain blockers section')
    this.assert('report generation < 5s', elapsed < 5000, `elapsed: ${elapsed}ms`)

    const progress = await StatusReportGenerator.calculateProgress()
    this.assert('calculateProgress', progress !== undefined, `overall: ${progress.overallProgress}%`)

    const risks = await StatusReportGenerator.identifyRisks()
    this.assert('identifyRisks', risks !== undefined, `risks: ${risks.length}`)

    const blockers = await StatusReportGenerator.identifyBlockers()
    this.assert('identifyBlockers', blockers !== undefined, `blockers: ${blockers.length}`)

    const saved = await StatusReportGenerator.saveStatusReport(41)
    this.assert('saveStatusReport', saved, 'report should be saved')
  }

  private async testMissingDataSources(): Promise<void> {
    const missing = await StatusReportGenerator.detectMissingDataSources()
    this.assert('detectMissingDataSources', missing !== undefined, `missing: ${missing.length}`)
  }
}

export const meetingStatusTest = new MeetingStatusIntegrationTest()