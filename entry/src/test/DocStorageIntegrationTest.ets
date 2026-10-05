import { DocPathResolver } from '../main/ets/docmanagement/storage/DocPathResolver'
import { DocStorageManager } from '../main/ets/docmanagement/storage/DocStorageManager'
import { DocConfigManager } from '../main/ets/docmanagement/storage/DocConfigManager'
import { DocType } from '../main/ets/docmanagement/enums/DocEnums'

interface TestResult {
  name: string
  passed: boolean
  detail: string
}

class DocStorageIntegrationTest {
  private results: TestResult[] = []

  private assert(name: string, condition: boolean, detail: string): void {
    this.results.push({ name: name, passed: condition, detail: detail })
  }

  async runAll(): Promise<TestResult[]> {
    this.results = []
    this.testPathResolution()
    this.testDepthValidation()
    await this.testFileOperations()
    await this.testAppendAndReplace()
    await this.testTraversalDetection()
    await this.testConfigManager()
    return this.results
  }

  private testPathResolution(): void {
    const plan = DocPathResolver.resolvePath(DocType.DEV_PLAN)
    this.assert('resolvePath DEV_PLAN', plan === 'dev-plan/development-plan.md', plan)

    const log = DocPathResolver.resolvePath(DocType.DEV_LOG, { year: 2026, month: 10 })
    this.assert('resolvePath DEV_LOG', log === 'dev-log/dev-log-2026-10.md', log)

    const changelog = DocPathResolver.resolvePath(DocType.CHANGELOG)
    this.assert('resolvePath CHANGELOG', changelog === 'changelog/CHANGELOG.md', changelog)

    const status = DocPathResolver.resolvePath(DocType.STATUS_REPORT, { year: 2026, week: 40 })
    this.assert('resolvePath STATUS_REPORT', status === 'status/status-report-2026-W40.md', status)

    const meeting = DocPathResolver.resolvePath(DocType.MEETING, { date: '2026-10-05' })
    this.assert('resolvePath MEETING', meeting === 'meeting/meeting-2026-10-05.md', meeting)

    const adr = DocPathResolver.resolvePath(DocType.ADR, { number: 1 })
    this.assert('resolvePath ADR', adr === 'adr/ADR-001.md', adr)

    const logArchive = DocPathResolver.resolveArchivePath(DocType.DEV_LOG, { year: 2026, month: 9 })
    this.assert('resolveArchivePath DEV_LOG', logArchive === 'dev-log/archive/dev-log-2026-09-summary.md', logArchive)

    const changelogArchive = DocPathResolver.resolveArchivePath(DocType.CHANGELOG, { version: '0.1.0' })
    this.assert('resolveArchivePath CHANGELOG', changelogArchive === 'changelog/archive/v0.1.0-snapshot.md', changelogArchive)
  }

  private testDepthValidation(): void {
    const ok = DocPathResolver.validateDepth('dev-log/archive/summary.md')
    this.assert('validateDepth 3-layer ok', ok, '3-layer path should be valid')

    const tooDeep = DocPathResolver.validateDepth('a/b/c/d/file.md')
    this.assert('validateDepth 4-layer rejected', !tooDeep, '4-layer path should be rejected')

    const traversal = DocPathResolver.validateDepth('../etc/passwd')
    this.assert('validateDepth traversal rejected', !traversal, 'traversal path should be rejected')

    const absolute = DocPathResolver.validateDepth('/data/etc')
    this.assert('validateDepth absolute rejected', !absolute, 'absolute path should be rejected')
  }

  private async testFileOperations(): Promise<void> {
    const saved = await DocStorageManager.save('dev-plan/test-save.md', '# Test Save')
    this.assert('save file', saved, 'save should return true')

    const exists = await DocStorageManager.exists('dev-plan/test-save.md')
    this.assert('exists file', exists, 'file should exist after save')

    const content = await DocStorageManager.load('dev-plan/test-save.md')
    this.assert('load file', content === '# Test Save', `loaded: "${content}"`)

    const listDir = await DocStorageManager.listDir('dev-plan')
    this.assert('listDir', listDir.includes('test-save.md'), `dir entries: ${JSON.stringify(listDir)}`)

    const deleted = await DocStorageManager.delete('dev-plan/test-save.md')
    this.assert('delete file', deleted, 'delete should return true')

    const existsAfter = await DocStorageManager.exists('dev-plan/test-save.md')
    this.assert('exists after delete', !existsAfter, 'file should not exist after delete')
  }

  private async testAppendAndReplace(): Promise<void> {
    await DocStorageManager.save('dev-plan/test-append.md', 'line1\n')
    const appended = await DocStorageManager.append('dev-plan/test-append.md', 'line2\n')
    this.assert('append content', appended, 'append should return true')
    const content = await DocStorageManager.load('dev-plan/test-append.md')
    this.assert('append content correct', content === 'line1\nline2\n', `content: "${content}"`)

    await DocStorageManager.save('dev-plan/test-replace.md', 'hello world')
    const replaced = await DocStorageManager.findAndReplace('dev-plan/test-replace.md', 'world', 'arkts')
    this.assert('findAndReplace', replaced, 'replace should return true')
    const replacedContent = await DocStorageManager.load('dev-plan/test-replace.md')
    this.assert('replace content correct', replacedContent === 'hello arkts', `content: "${replacedContent}"`)

    await DocStorageManager.delete('dev-plan/test-append.md')
    await DocStorageManager.delete('dev-plan/test-replace.md')
  }

  private async testTraversalDetection(): Promise<void> {
    let thrown = false
    try {
      await DocStorageManager.save('../escape.md', 'malicious')
    } catch (e) {
      thrown = true
    }
    this.assert('traversal save throws', thrown, 'traversal path should throw')

    const loadEscaped = await DocStorageManager.load('../escape.md')
    this.assert('traversal load returns null', loadEscaped === null, 'traversal load should fail safely')
  }

  private async testConfigManager(): Promise<void> {
    const loaded = await DocConfigManager.loadConfig()
    this.assert('loadConfig', loaded !== undefined, `config loaded: retention=${loaded.archiveRetentionDays}`)

    const config = DocConfigManager.get()
    this.assert('get config', config.templateVersion.length > 0, `templateVersion: ${config.templateVersion}`)
  }
}

export const docStorageTest = new DocStorageIntegrationTest()