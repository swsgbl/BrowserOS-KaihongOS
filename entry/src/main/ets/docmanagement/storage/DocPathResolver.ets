import { fileIo as fs } from '@kit.CoreFileKit'
import { DocType } from '../enums/DocEnums'
import { PathParams } from '../models/DocDataTypes'
import { DocErrorCodes } from '../common/DocErrorCodes'
import { ErrorHandler, AppError } from '../../infra/ErrorHandler'

interface DepthErrorContext {
  path: string
}

class DocPathResolverImpl {
  static readonly DOC_ROOT: string = '.codeartsdoer/specs'
  static readonly MAX_DEPTH: number = 3

  static pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`
  }

  static pad3(n: number): string {
    if (n < 10) {
      return `00${n}`
    }
    if (n < 100) {
      return `0${n}`
    }
    return `${n}`
  }

  static resolvePath(docType: DocType, params?: PathParams): string {
    switch (docType) {
      case DocType.DEV_PLAN:
        return 'dev-plan/development-plan.md'
      case DocType.DEV_LOG: {
        const year = params?.year !== undefined ? params.year : 1970
        const month = params?.month !== undefined ? params.month : 1
        if (year < 1970 || month < 1 || month > 12) {
          throw new AppError(DocErrorCodes.DOC_PATH_001, `Invalid dev-log params: year=${year}, month=${month}`)
        }
        return `dev-log/dev-log-${year}-${this.pad2(month)}.md`
      }
      case DocType.CHANGELOG:
        return 'changelog/CHANGELOG.md'
      case DocType.STATUS_REPORT: {
        const year = params?.year !== undefined ? params.year : 1970
        const week = params?.week !== undefined ? params.week : 1
        if (year < 1970 || week < 1 || week > 53) {
          throw new AppError(DocErrorCodes.DOC_PATH_001, `Invalid status-report params: year=${year}, week=${week}`)
        }
        return `status/status-report-${year}-W${week}.md`
      }
      case DocType.MEETING: {
        const date = params?.date
        if (!date) {
          throw new AppError(DocErrorCodes.DOC_PATH_001, 'Meeting path requires date param (YYYY-MM-DD)')
        }
        return `meeting/meeting-${date}.md`
      }
      case DocType.ADR: {
        const num = params?.number
        if (num === undefined || num < 1) {
          throw new AppError(DocErrorCodes.DOC_PATH_001, 'ADR path requires number param (>=1)')
        }
        return `adr/ADR-${this.pad3(num)}.md`
      }
      default:
        throw new AppError(DocErrorCodes.DOC_PATH_001, `Unknown doc type: ${docType}`)
    }
  }

  static resolveArchivePath(docType: DocType, params?: PathParams): string {
    switch (docType) {
      case DocType.DEV_LOG: {
        const year = params?.year !== undefined ? params.year : 1970
        const month = params?.month !== undefined ? params.month : 1
        return `dev-log/archive/dev-log-${year}-${this.pad2(month)}-summary.md`
      }
      case DocType.CHANGELOG: {
        const version = params?.version
        if (!version) {
          throw new AppError(DocErrorCodes.DOC_PATH_001, 'Changelog archive path requires version param')
        }
        return `changelog/archive/v${version}-snapshot.md`
      }
      default:
        throw new AppError(DocErrorCodes.DOC_PATH_001, `Unsupported archive doc type: ${docType}`)
    }
  }

  static validateDepth(relativePath: string): boolean {
    if (!relativePath || relativePath.length === 0) {
      return false
    }
    const depthErrorContext: DepthErrorContext = { path: relativePath }
    if (relativePath.includes('..') || relativePath.startsWith('/') || relativePath.startsWith('\\')) {
      ErrorHandler.handle(new AppError(DocErrorCodes.DOC_PATH_002, `Path traversal detected: ${relativePath}`, depthErrorContext))
      return false
    }
    const segments = relativePath.split('/')
    if (segments.length > this.MAX_DEPTH) {
      ErrorHandler.handle(new AppError(DocErrorCodes.DOC_PATH_002, `Path depth ${segments.length} exceeds ${this.MAX_DEPTH}`, depthErrorContext))
      return false
    }
    return true
  }

  static ensureDir(dirPath: string): void {
    try {
      fs.mkdirSync(dirPath, true)
    } catch (e) {
      ErrorHandler.handle(new AppError(DocErrorCodes.DOC_PATH_003, `Dir create failed: ${dirPath}, ${e}`))
    }
  }

  static getFsRoot(): string {
    return `.codeartsdoer/specs`
  }
}

export const DocPathResolver = DocPathResolverImpl