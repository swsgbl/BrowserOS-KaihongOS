import { ChangelogManager } from '../main/ets/docmanagement/business/ChangelogManager'
import { ADRManager } from '../main/ets/docmanagement/business/ADRManager'
import { ChangeType, ADRStatus } from '../main/ets/docmanagement/enums/DocEnums'

interface TestResult {
  name: string
  passed: boolean
  detail: string
}

class ChangelogADRIntegrationTest {
  private results: TestResult[] = []

  private assert(name: string, condition: boolean, detail: string): void {
    this.results.push({ name: name, passed: condition, detail: detail })
  }

  async runAll(): Promise<TestResult[]> {
    this.results = []
    await this.testVersionFlow()
    await this.testSemVerValidation()
    await this.testPrerequisites()
    await this.testADRFlow()
    await this.testADRConstraints()
    return this.results
  }

  private async testVersionFlow(): Promise<void> {
    const created = await ChangelogManager.createVersion('0.1.0', '2026-10-05')
    this.assert('createVersion', created, 'version 0.1.0 should be created')

    const added = await ChangelogManager.addChangeEntry('0.1.0', ChangeType.ADDED, '新增文档管理体系')
    this.assert('addChangeEntry ADDED', added, 'change entry should be added')

    const changes = await ChangelogManager.getVersionChanges('0.1.0')
    this.assert('getVersionChanges', changes.length > 0, `count: ${changes.length}`)

    const archived = await ChangelogManager.archiveVersionSnapshot('0.1.0')
    this.assert('archiveVersionSnapshot', archived, 'version snapshot should be archived')
  }

  private async testSemVerValidation(): Promise<void> {
    let invalidFormat = false
    try {
      await ChangelogManager.createVersion('abc', '2026-10-05')
    } catch (e) {
      invalidFormat = true
    }
    this.assert('invalid SemVer rejected', invalidFormat, 'non-SemVer should throw')

    let duplicate = false
    try {
      await ChangelogManager.createVersion('0.1.0', '2026-10-05')
    } catch (e) {
      duplicate = true
    }
    this.assert('duplicate version rejected', duplicate, 'duplicate version should throw')

    let skipDetected = false
    try {
      await ChangelogManager.createVersion('0.3.0', '2026-10-05')
    } catch (e) {
      skipDetected = true
    }
    this.assert('version skip rejected', skipDetected, '0.1.0 -> 0.3.0 should throw')

    let downgrade = false
    try {
      await ChangelogManager.createVersion('0.0.5', '2026-10-05')
    } catch (e) {
      downgrade = true
    }
    this.assert('version downgrade rejected', downgrade, 'downgrade should throw')
  }

  private async testPrerequisites(): Promise<void> {
    const result = await ChangelogManager.checkReleasePrerequisites('0.2.0')
    this.assert('checkReleasePrerequisites returns result', result !== undefined, `allMet: ${result.allMet}, unmet: ${JSON.stringify(result.unmetItems)}`)
    this.assert('prerequisites details count', result.details.length === 4, `details: ${result.details.length}`)
  }

  private async testADRFlow(): Promise<void> {
    const adrId = await ADRManager.createADR({
      title: '测试决策：文档存储方案',
      context: '需要选择文档存储格式',
      decision: '采用 Markdown 格式存储在 specs 目录',
      consequences: '文档可在任意编辑器阅读',
      sddLinks: []
    })
    this.assert('createADR', adrId.length > 0, `created: ${adrId}`)

    const list = await ADRManager.getADRList()
    this.assert('getADRList', list.length > 0, `count: ${list.length}`)

    const detail = await ADRManager.getADRDetail(adrId)
    this.assert('getADRDetail', detail !== null && detail.status === ADRStatus.PROPOSED, `status: ${detail ? detail.status : 'null'}`)

    const linked = await ADRManager.linkSDDDocument(adrId, '.codeartsdoer/specs/doc_management/spec.md', '5.3 版本变更管理')
    this.assert('linkSDDDocument', linked, 'SDD doc should be linked')

    const accepted = await ADRManager.updateADRStatus(adrId, ADRStatus.ACCEPTED)
    this.assert('PROPOSED->ACCEPTED', accepted, 'legal transition should succeed')

    const conflicts = await ADRManager.detectADRConflicts()
    this.assert('detectADRConflicts', conflicts.length === 0, `conflicts: ${conflicts.length}`)
  }

  private async testADRConstraints(): Promise<void> {
    let illegalTransition = false
    try {
      await ADRManager.updateADRStatus('ADR-999', ADRStatus.ACCEPTED)
    } catch (e) {
      illegalTransition = true
    }
    this.assert('unknown ADR update rejected', illegalTransition, 'unknown ADR should throw')

    const newId = await ADRManager.createADR({
      title: '替代测试 ADR',
      context: '测试替代流程',
      decision: '新决策',
      consequences: '旧 ADR 变为已替代',
      sddLinks: []
    })
    await ADRManager.updateADRStatus(newId, ADRStatus.ACCEPTED)
    const superseded = await ADRManager.supersedeADR(newId, {
      title: '新替代 ADR',
      context: '替代测试',
      decision: '更新的决策',
      consequences: '旧 ADR 变为已替代',
      sddLinks: []
    })
    this.assert('supersedeADR', superseded.length > 0, `new ADR: ${superseded}`)

    const oldDetail = await ADRManager.getADRDetail(newId)
    this.assert('old ADR becomes SUPERSEDED', oldDetail !== null && oldDetail.status === ADRStatus.SUPERSEDED, `status: ${oldDetail ? oldDetail.status : 'null'}`)
  }
}

export const changelogADRTest = new ChangelogADRIntegrationTest()