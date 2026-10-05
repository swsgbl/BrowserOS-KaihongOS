import { DocStorageManager } from './storage/DocStorageManager'
import { DocPathResolver } from './storage/DocPathResolver'
import { DocTemplateManager } from './support/DocTemplateManager'
import { DocType } from './enums/DocEnums'
import { DocErrorCodes } from './common/DocErrorCodes'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'

interface InitCheckResult {
  allDirsCreated: boolean
  missingDirs: string[]
}

class DocManagementInitializerImpl {
  private static readonly DIRS: string[] = [
    'dev-plan',
    'dev-log',
    'changelog',
    'status',
    'meeting',
    'adr'
  ]

  private static readonly ARCHIVE_DIRS: string[] = [
    'dev-log/archive',
    'changelog/archive'
  ]

  async initialize(): Promise<InitCheckResult> {
    const fsRoot = DocPathResolver.getFsRoot()
    DocPathResolver.ensureDir(fsRoot)
    for (const dir of DocManagementInitializerImpl.DIRS) {
      DocPathResolver.ensureDir(`${fsRoot}/${dir}`)
    }
    for (const dir of DocManagementInitializerImpl.ARCHIVE_DIRS) {
      DocPathResolver.ensureDir(`${fsRoot}/${dir}`)
    }
    await this.initChangelogFile()
    await this.initADRIndexFile()
    await this.initDevPlanFile()
    const check = await this.verifyDirectories()
    return check
  }

  private async initChangelogFile(): Promise<void> {
    const exists = await DocStorageManager.exists('changelog/CHANGELOG.md')
    if (!exists) {
      const params: Record<string, Object> = {
        'version': '',
        'date': '',
        'change-description': ''
      }
      const content = DocTemplateManager.createFromTemplate(DocType.CHANGELOG, params)
      await DocStorageManager.save('changelog/CHANGELOG.md', content)
    }
  }

  private async initADRIndexFile(): Promise<void> {
    const exists = await DocStorageManager.exists('adr/ADR-INDEX.md')
    if (!exists) {
      const content = DocTemplateManager.getADRIndexTemplate()
      await DocStorageManager.save('adr/ADR-INDEX.md', content)
    }
  }

  private async initDevPlanFile(): Promise<void> {
    const exists = await DocStorageManager.exists('dev-plan/development-plan.md')
    if (!exists) {
      const content = `# BrowserOS KaihongOS 开发计划\n\n## 里程碑总览\n\n| 编号 | 名称 | 描述 | 目标交付物 | 计划完成日期 | 实际完成日期 | 状态 |\n|------|------|------|-----------|-------------|-------------|------|\n\n## 任务分解\n\n## 时间线\n\n## 资源分配\n`
      await DocStorageManager.save('dev-plan/development-plan.md', content)
    }
  }

  private async verifyDirectories(): Promise<InitCheckResult> {
    const missingDirs: string[] = []
    const fsRoot = DocPathResolver.getFsRoot()
    for (const dir of DocManagementInitializerImpl.DIRS) {
      const probeFile = `${dir}/.probe`
      const saved = await DocStorageManager.save(probeFile, 'probe')
      if (!saved) {
        missingDirs.push(`${fsRoot}/${dir}`)
      } else {
        await DocStorageManager.delete(probeFile)
      }
    }
    const result: InitCheckResult = {
      allDirsCreated: missingDirs.length === 0,
      missingDirs: missingDirs
    }
    return result
  }

  async validateDepthConstraints(): Promise<boolean> {
    for (const dir of DocManagementInitializerImpl.DIRS) {
      const testPath = `${dir}/test.md`
      if (!DocPathResolver.validateDepth(testPath)) {
        return false
      }
    }
    return true
  }
}

export const DocManagementInitializer = new DocManagementInitializerImpl()