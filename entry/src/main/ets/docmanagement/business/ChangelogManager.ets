import { ChangeEntry } from '../models/DocModels'
import { PrerequisiteCheckResult, PrerequisiteDetail } from '../models/DocDataTypes'
import { ChangeType } from '../enums/DocEnums'
import { DocStorageManager } from '../storage/DocStorageManager'
import { DocPathResolver } from '../storage/DocPathResolver'
import { DocType } from '../enums/DocEnums'
import { DocErrorCodes } from '../common/DocErrorCodes'
import { DevPlanManager } from './DevPlanManager'
import { DevLogManager } from './DevLogManager'
import { TaskStatus, ProblemStatus } from '../enums/DocEnums'
import { ErrorHandler, AppError } from '../../infra/ErrorHandler'
import { EventBus, EventBusEvents } from '../../infra/EventBus'

const MAX_CHANGE_DESC: number = 200
const HAP_PATTERN: RegExp = /entry-.*\.hap/
const CHANGELOG_DATA_FILE: string = 'changelog-data.json'
const SENSITIVE_PATTERN: RegExp = /(password|secret|token|api[_-]?key|apikey|passwd)\s*[:=]/i

class ChangelogManagerImpl {
  private changes: ChangeEntry[] = []
  private versions: string[] = []
  private pendingHapFileName: string = ''
  private pendingCommitRange: string = ''

  private isValidSemVer(version: string): boolean {
    const regex = /^\d+\.\d+\.\d+$/
    if (!regex.test(version)) {
      return false
    }
    const parts = version.split('.')
    for (const p of parts) {
      const n = parseInt(p)
      if (isNaN(n) || n < 0) {
        return false
      }
    }
    return true
  }

  private compareVersions(a: string, b: string): number {
    const pa = a.split('.')
    const pb = b.split('.')
    for (let i = 0; i < 3; i++) {
      const na = parseInt(pa[i])
      const nb = parseInt(pb[i])
      if (na !== nb) {
        return na - nb
      }
    }
    return 0
  }

  async validateVersionNumber(version: string): Promise<boolean> {
    if (!this.isValidSemVer(version)) {
      throw new AppError(DocErrorCodes.CHANGELOG_001, `Invalid SemVer: ${version}`)
    }
    for (const v of this.versions) {
      if (v === version) {
        throw new AppError(DocErrorCodes.CHANGELOG_003, `Version already exists: ${version}`)
      }
    }
    if (this.versions.length > 0) {
      const sorted = this.versions.slice().sort((a, b) => this.compareVersions(a, b))
      const latest = sorted[sorted.length - 1]
      const cmp = this.compareVersions(version, latest)
      if (cmp <= 0) {
        throw new AppError(DocErrorCodes.CHANGELOG_002, `Version must be greater than latest ${latest}`)
      }
      const latestParts = latest.split('.')
      const newParts = version.split('.')
      const latestMajor = parseInt(latestParts[0])
      const newMajor = parseInt(newParts[0])
      const latestMinor = parseInt(latestParts[1])
      const newMinor = parseInt(newParts[1])
      if (newMajor > latestMajor + 1) {
        throw new AppError(DocErrorCodes.CHANGELOG_002, `Major skip detected: ${latest} -> ${version}`)
      }
      if (newMajor === latestMajor) {
        if (newMinor > latestMinor + 1) {
          throw new AppError(DocErrorCodes.CHANGELOG_002, `Minor skip detected: ${latest} -> ${version}`)
        }
        if (newMinor === latestMinor) {
          const expectedPatch = parseInt(latestParts[2]) + 1
          if (parseInt(newParts[2]) > expectedPatch) {
            throw new AppError(DocErrorCodes.CHANGELOG_002, `Version skip detected: ${latest} -> ${version}`)
          }
        }
      }
    }
    return true
  }

  setHapBuildInfo(hapFileName: string, commitRange: string): void {
    this.pendingHapFileName = hapFileName
    this.pendingCommitRange = commitRange
  }

  async createVersion(version: string, releaseDate: string): Promise<boolean> {
    await this.validateVersionNumber(version)
    this.versions.push(version)
    for (const c of this.changes) {
      if (c.version === version) {
        c.hapFileName = this.pendingHapFileName
        c.commitRange = this.pendingCommitRange
        c.releaseDate = releaseDate
      }
    }
    await this.saveChangelogDocument()
    EventBus.emit(EventBusEvents.DOC_VERSION_RELEASED, { version: version, releaseDate: releaseDate })
    return true
  }

  async addChangeEntry(version: string, type: ChangeType, description: string): Promise<boolean> {
    if (!description || description.length > MAX_CHANGE_DESC) {
      throw new AppError(DocErrorCodes.CHANGELOG_005, `Change description required, max ${MAX_CHANGE_DESC} chars`)
    }
    if (SENSITIVE_PATTERN.test(description)) {
      throw new AppError(DocErrorCodes.CHANGELOG_005, `Change description contains sensitive info`)
    }
    if (type !== ChangeType.ADDED && type !== ChangeType.CHANGED && type !== ChangeType.FIXED && type !== ChangeType.REMOVED) {
      throw new AppError(DocErrorCodes.CHANGELOG_005, `Invalid change type: ${type}`)
    }
    const entry: ChangeEntry = {
      version: version,
      type: type,
      description: description,
      commitRange: '',
      hapFileName: '',
      releaseDate: ''
    }
    this.changes.push(entry)
    await this.saveChangelogDocument()
    return true
  }

  async checkReleasePrerequisites(version: string): Promise<PrerequisiteCheckResult> {
    const details: PrerequisiteDetail[] = []

    const milestones = await DevPlanManager.getMilestones()
    let tasksDone = true
    for (const m of milestones) {
      for (const t of m.tasks) {
        if (t.status !== TaskStatus.COMPLETED) {
          tasksDone = false
        }
      }
    }
    const detail1: PrerequisiteDetail = {
      name: '所有计划任务已完成',
      met: tasksDone,
      description: tasksDone ? '全部任务已完成' : '存在未完成任务'
    }
    details.push(detail1)

    const problemsResolved = await this.checkSeriousProblemsResolved()
    const detail2: PrerequisiteDetail = {
      name: '所有严重缺陷已修复',
      met: problemsResolved,
      description: problemsResolved ? '无未解决的严重缺陷' : '存在未解决缺陷'
    }
    details.push(detail2)

    const hasChanges = this.changes.some(c => c.version === version)
    const detail3: PrerequisiteDetail = {
      name: '变更日志已编写',
      met: hasChanges,
      description: hasChanges ? `版本 ${version} 已有变更条目` : `版本 ${version} 无变更条目`
    }
    details.push(detail3)

    const hapExists = await this.checkHapBuilt()
    const detail4: PrerequisiteDetail = {
      name: 'HAP 包已构建成功',
      met: hapExists,
      description: hapExists ? 'HAP 包存在' : '未找到 HAP 包'
    }
    details.push(detail4)

    const unmetItems: string[] = []
    for (const d of details) {
      if (!d.met) {
        unmetItems.push(d.name)
      }
    }
    const result: PrerequisiteCheckResult = {
      allMet: unmetItems.length === 0,
      unmetItems: unmetItems,
      details: details
    }
    return result
  }

  private async checkSeriousProblemsResolved(): Promise<boolean> {
    const longStanding = await DevLogManager.getLongStandingProblems()
    if (longStanding.length > 0) {
      return false
    }
    const unresolved = await DevLogManager.getUnresolvedProblems()
    if (unresolved.length > 0) {
      return false
    }
    return true
  }

  private async checkHapBuilt(): Promise<boolean> {
    if (this.pendingHapFileName.length > 0 && HAP_PATTERN.test(this.pendingHapFileName)) {
      return true
    }
    return false
  }

  async getChangelog(): Promise<ChangeEntry[]> {
    return this.changes
  }

  async getVersionChanges(version: string): Promise<ChangeEntry[]> {
    const result: ChangeEntry[] = []
    for (const c of this.changes) {
      if (c.version === version) {
        result.push(c)
      }
    }
    return result
  }

  async archiveVersionSnapshot(version: string): Promise<boolean> {
    try {
      const archivePath = DocPathResolver.resolveArchivePath(DocType.CHANGELOG, { version: version })
      let doc = `# 版本快照 - ${version}\n\n`
      doc += `## 版本变更\n\n`
      for (const c of this.changes) {
        if (c.version === version) {
          doc += `- [${c.type}] ${c.description}\n`
        }
      }
      doc += `\n## 开发计划快照\n\n`
      const planDoc = await DocStorageManager.load('dev-plan/development-plan.md')
      if (planDoc) {
        doc += planDoc + '\n'
      }
      doc += `\n## 状态报告快照\n\n`
      const year = new Date().getFullYear()
      const week = this.currentWeek()
      const statusDoc = await DocStorageManager.load(`status/status-report-${year}-W${week}.md`)
      if (statusDoc) {
        doc += statusDoc + '\n'
      } else {
        doc += `（本周状态报告未生成）\n`
      }
      await DocStorageManager.save(archivePath, doc)
      return true
    } catch (e) {
      return false
    }
  }

  private currentWeek(): number {
    const d = new Date()
    const start = new Date(d.getFullYear(), 0, 1)
    const diff = d.getTime() - start.getTime()
    const oneWeek = 7 * 24 * 60 * 60 * 1000
    return Math.ceil(diff / oneWeek)
  }

  async saveChangelogDocument(): Promise<boolean> {
    try {
      let doc = `# Changelog\n\n本文件记录 BrowserOS KaihongOS 项目的所有版本变更，遵循 Keep a Changelog 规范。\n\n`
      const sortedVersions = this.versions.slice().sort((a, b) => this.compareVersions(b, a))
      for (const version of sortedVersions) {
        doc += `## [${version}]\n\n`
        for (const type of [ChangeType.ADDED, ChangeType.CHANGED, ChangeType.FIXED, ChangeType.REMOVED]) {
          const entries: ChangeEntry[] = []
          for (const c of this.changes) {
            if (c.version === version && c.type === type) {
              entries.push(c)
            }
          }
          if (entries.length > 0) {
            doc += `### ${type}\n`
            for (const e of entries) {
              doc += `- ${e.description}\n`
            }
            doc += `\n`
          }
        }
      }
      await DocStorageManager.save('changelog/CHANGELOG.md', doc)
      await DocStorageManager.save(`changelog/${CHANGELOG_DATA_FILE}`, JSON.stringify({
        versions: this.versions,
        changes: this.changes
      }))
      return true
    } catch (e) {
      ErrorHandler.handle(new AppError(DocErrorCodes.CHANGELOG_004, `Save changelog failed: ${e}`))
      return false
    }
  }
  async loadDataSnapshot(): Promise<void> {
    const json = await DocStorageManager.load(`changelog/${CHANGELOG_DATA_FILE}`)
    if (json) {
      try {
        const parsed = JSON.parse(json) as Record<string, Object>
        const vs = parsed['versions']
        if (Array.isArray(vs)) {
          this.versions = vs as string[]
        }
        const cs = parsed['changes']
        if (Array.isArray(cs)) {
          this.changes = cs as ChangeEntry[]
        }
      } catch (e) {
      }
    }
  }
}

export const ChangelogManager = new ChangelogManagerImpl()