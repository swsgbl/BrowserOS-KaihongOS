import { ADR, SDDLink, ADRStatus } from '../models/DocModels'
import { ADRData, ADRConflict } from '../models/DocDataTypes'
import { DocStorageManager } from '../storage/DocStorageManager'
import { DocPathResolver } from '../storage/DocPathResolver'
import { DocType, AccessLevel } from '../enums/DocEnums'
import { DocTemplateManager } from '../support/DocTemplateManager'
import { DocErrorCodes } from '../common/DocErrorCodes'
import { ErrorHandler, AppError } from '../../infra/ErrorHandler'

const MAX_TITLE_LENGTH: number = 80
const ADR_DATA_FILE: string = 'adr-data.json'

class ADRManagerImpl {
  private adrs: ADR[] = []
  private nextSeq: number = 1

  private today(): string {
    const d = new Date()
    return `${d.getFullYear()}-${DocPathResolver.pad2(d.getMonth() + 1)}-${DocPathResolver.pad2(d.getDate())}`
  }

  private findADR(adrId: string): ADR | undefined {
    for (const a of this.adrs) {
      if (a.id === adrId) {
        return a
      }
    }
    return undefined
  }

  private canTransitionADR(from: ADRStatus, to: ADRStatus): boolean {
    if (from === ADRStatus.PROPOSED) {
      return to === ADRStatus.ACCEPTED || to === ADRStatus.DEPRECATED
    }
    if (from === ADRStatus.ACCEPTED) {
      return to === ADRStatus.SUPERSEDED
    }
    return false
  }

  async createADR(data: ADRData): Promise<string> {
    if (!data.title || data.title.length > MAX_TITLE_LENGTH) {
      throw new AppError(DocErrorCodes.ADR_001, `ADR title required, max ${MAX_TITLE_LENGTH} chars`)
    }
    const num = this.nextSeq
    this.nextSeq++
    const id = `ADR-${DocPathResolver.pad3(num)}`
    const adr: ADR = {
      id: id,
      number: String(num),
      title: data.title,
      status: ADRStatus.PROPOSED,
      accessLevel: AccessLevel.INTERNAL,
      context: data.context,
      decision: data.decision,
      consequences: data.consequences,
      sddLinks: data.sddLinks,
      supersededBy: '',
      supersedes: '',
      createdDate: this.today(),
      acceptedDate: ''
    }
    this.adrs.push(adr)
    await this.saveADRDocument(id)
    await this.updateADRIndex()
    return id
  }

  async updateADRStatus(adrId: string, status: ADRStatus): Promise<boolean> {
    const adr = this.findADR(adrId)
    if (!adr) {
      throw new AppError(DocErrorCodes.ADR_002, `ADR not found: ${adrId}`)
    }
    if (!this.canTransitionADR(adr.status, status)) {
      throw new AppError(DocErrorCodes.ADR_003, `Illegal ADR transition: ${adr.status} -> ${status}`)
    }
    adr.status = status
    if (status === ADRStatus.ACCEPTED) {
      adr.acceptedDate = this.today()
    }
    await this.saveADRDocument(adrId)
    await this.updateADRIndex()
    return true
  }

  async supersedeADR(oldAdrId: string, newAdrData: ADRData): Promise<string> {
    const oldADR = this.findADR(oldAdrId)
    if (!oldADR) {
      throw new AppError(DocErrorCodes.ADR_002, `ADR not found: ${oldAdrId}`)
    }
    if (oldADR.status !== ADRStatus.ACCEPTED) {
      throw new AppError(DocErrorCodes.ADR_003, `Only accepted ADR can be superseded: ${oldAdrId} is ${oldADR.status}`)
    }
    const newId = await this.createADR(newAdrData)
    const newADR = this.findADR(newId)
    if (newADR) {
      newADR.status = ADRStatus.ACCEPTED
      newADR.acceptedDate = this.today()
      newADR.supersedes = oldAdrId
      await this.saveADRDocument(newId)
    }
    oldADR.status = ADRStatus.SUPERSEDED
    oldADR.supersededBy = newId
    await this.saveADRDocument(oldAdrId)
    await this.updateADRIndex()
    return newId
  }

  async linkSDDDocument(adrId: string, docPath: string, section: string): Promise<boolean> {
    const adr = this.findADR(adrId)
    if (!adr) {
      throw new AppError(DocErrorCodes.ADR_002, `ADR not found: ${adrId}`)
    }
    if (adr.status === ADRStatus.ACCEPTED) {
      throw new AppError(DocErrorCodes.ADR_005, `Cannot modify accepted ADR: ${adrId}`)
    }
    const link: SDDLink = {
      docPath: docPath,
      section: section
    }
    adr.sddLinks.push(link)
    await this.saveADRDocument(adrId)
    return true
  }

  async setADRAccessLevel(adrId: string, level: AccessLevel): Promise<boolean> {
    const adr = this.findADR(adrId)
    if (!adr) {
      throw new AppError(DocErrorCodes.ADR_002, `ADR not found: ${adrId}`)
    }
    adr.accessLevel = level
    await this.saveADRDocument(adrId)
    return true
  }

  async getADRsByAccessLevel(level: AccessLevel): Promise<ADR[]> {
    const result: ADR[] = []
    for (const a of this.adrs) {
      if (a.accessLevel === level) {
        result.push(a)
      }
    }
    return result
  }

  async getADRList(): Promise<ADR[]> {
    return this.adrs
  }

  async getADRDetail(adrId: string): Promise<ADR | null> {
    const adr = this.findADR(adrId)
    return adr !== undefined ? adr : null
  }

  private statusToText(status: ADRStatus): string {
    if (status === ADRStatus.PROPOSED) {
      return '提议'
    }
    if (status === ADRStatus.ACCEPTED) {
      return '已接受'
    }
    if (status === ADRStatus.DEPRECATED) {
      return '已废弃'
    }
    return '已替代'
  }

  async updateADRIndex(): Promise<boolean> {
    try {
      let doc = `# ADR 索引\n\n`
      doc += `| 编号 | 标题 | 状态 | 访问级别 | 创建日期 | 接受日期 |\n`
      doc += `|------|------|------|---------|---------|---------|\n`
      for (const a of this.adrs) {
        doc += `| ${a.id} | ${a.title} | ${this.statusToText(a.status)} | ${a.accessLevel} | ${a.createdDate} | ${a.acceptedDate} |\n`
      }
      await DocStorageManager.save('adr/ADR-INDEX.md', doc)
      await DocStorageManager.save(`adr/${ADR_DATA_FILE}`, JSON.stringify({
        nextSeq: this.nextSeq,
        adrs: this.adrs
      }))
      return true
    } catch (e) {
      return false
    }
  }

  async detectADRConflicts(): Promise<ADRConflict[]> {
    const conflicts: ADRConflict[] = []
    for (const a of this.adrs) {
      if (a.status !== ADRStatus.ACCEPTED) {
        continue
      }
      for (const link of a.sddLinks) {
        const content = await DocStorageManager.load(link.docPath)
        if (content === null) {
          const conflict: ADRConflict = {
            adrId: a.id,
            sddDocPath: link.docPath,
            section: link.section,
            description: '关联的 SDD 文档不存在'
          }
          conflicts.push(conflict)
        }
      }
    }
    return conflicts
  }

  async saveADRDocument(adrId: string): Promise<boolean> {
    try {
      const adr = this.findADR(adrId)
      if (!adr) {
        return false
      }
      const num = parseInt(adr.number)
      const relativePath = DocPathResolver.resolvePath(DocType.ADR, { number: num })
      const params: Record<string, Object> = {
        'number': adr.number,
        'title': adr.title,
        'status': this.statusToText(adr.status),
        'access-level': adr.accessLevel,
        'context': adr.context,
        'decision': adr.decision,
        'consequences': adr.consequences,
        'doc-path': adr.sddLinks.length > 0 ? adr.sddLinks[0].docPath : '',
        'section': adr.sddLinks.length > 0 ? adr.sddLinks[0].section : ''
      }
      const content = DocTemplateManager.createFromTemplate(DocType.ADR, params)
      await DocStorageManager.save(relativePath, content)
      return true
    } catch (e) {
      ErrorHandler.handle(new AppError(DocErrorCodes.ADR_003, `Save ADR failed: ${e}`))
      return false
    }
  }

  async loadDataSnapshot(): Promise<void> {
    const json = await DocStorageManager.load(`adr/${ADR_DATA_FILE}`)
    if (json) {
      try {
        const parsed = JSON.parse(json) as Record<string, Object>
        this.nextSeq = typeof parsed['nextSeq'] === 'number' ? parsed['nextSeq'] as number : 1
        const as = parsed['adrs']
        if (Array.isArray(as)) {
          this.adrs = as as ADR[]
        }
      } catch (e) {
      }
    }
  }
}

export const ADRManager = new ADRManagerImpl()