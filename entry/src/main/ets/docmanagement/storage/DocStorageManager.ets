import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { DocPathResolver } from './DocPathResolver'
import { DocErrorCodes } from '../common/DocErrorCodes'
import { ErrorHandler, AppError } from '../../infra/ErrorHandler'

interface StgErrorContext {
  path: string
}

class DocStorageManagerImpl {
  private fsRoot: string = `${DocPathResolver.DOC_ROOT}`

  setFsRoot(root: string): void {
    this.fsRoot = root
  }

  private resolveFullPath(relativePath: string): string {
    if (!DocPathResolver.validateDepth(relativePath)) {
      throw new AppError(DocErrorCodes.DOC_STG_004, `Path traversal or invalid: ${relativePath}`)
    }
    return `${this.fsRoot}/${relativePath}`
  }

  async save(relativePath: string, content: string): Promise<boolean> {
    try {
      const fullPath = this.resolveFullPath(relativePath)
      const dirPath = fullPath.substring(0, fullPath.lastIndexOf('/'))
      DocPathResolver.ensureDir(dirPath)
      const file = fs.openSync(fullPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, content)
      fs.closeSync(file)
      return true
    } catch (e) {
      if (e instanceof AppError) {
        ErrorHandler.handle(e)
        return false
      }
      const stgContext: StgErrorContext = { path: relativePath }
      ErrorHandler.handle(new AppError(DocErrorCodes.DOC_STG_001, `Save failed: ${e}`, stgContext))
      return false
    }
  }

  async load(relativePath: string): Promise<string | null> {
    let fullPath = ''
    try {
      fullPath = this.resolveFullPath(relativePath)
    } catch (e) {
      return null
    }
    let file: fs.File
    try {
      file = fs.openSync(fullPath, fs.OpenMode.READ_ONLY)
    } catch (e) {
      return null
    }
    try {
      const stat = fs.statSync(fullPath)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      const view = new Uint8Array(buffer)
      const decoder = util.TextDecoder.create('utf-8')
      return decoder.decodeToString(view)
    } catch (e) {
      const stgContext: StgErrorContext = { path: relativePath }
      ErrorHandler.handle(new AppError(DocErrorCodes.DOC_STG_002, `Load failed: ${e}`, stgContext))
      try {
        fs.closeSync(file)
      } catch (err) {
      }
      return null
    }
  }

  async delete(relativePath: string): Promise<boolean> {
    let fullPath = ''
    try {
      fullPath = this.resolveFullPath(relativePath)
    } catch (e) {
      return false
    }
    try {
      fs.unlinkSync(fullPath)
      return true
    } catch (e) {
      const stgContext: StgErrorContext = { path: relativePath }
      ErrorHandler.handle(new AppError(DocErrorCodes.DOC_STG_003, `Delete failed: ${e}`, stgContext))
      return false
    }
  }

  async exists(relativePath: string): Promise<boolean> {
    try {
      const fullPath = this.resolveFullPath(relativePath)
      fs.accessSync(fullPath)
      return true
    } catch (e) {
      return false
    }
  }

  async listDir(relativePath: string): Promise<string[]> {
    try {
      const fullPath = this.resolveFullPath(relativePath)
      const entries = fs.listFileSync(fullPath)
      return entries
    } catch (e) {
      return []
    }
  }

  async append(relativePath: string, content: string): Promise<boolean> {
    try {
      const existing = await this.load(relativePath)
      const merged = existing !== null ? existing + content : content
      return await this.save(relativePath, merged)
    } catch (e) {
      const stgContext: StgErrorContext = { path: relativePath }
      ErrorHandler.handle(new AppError(DocErrorCodes.DOC_STG_005, `Append failed: ${e}`, stgContext))
      return false
    }
  }

  async findAndReplace(relativePath: string, pattern: string, replacement: string): Promise<boolean> {
    const content = await this.load(relativePath)
    if (content === null) {
      return false
    }
    const updated = content.split(pattern).join(replacement)
    return await this.save(relativePath, updated)
  }
}

export const DocStorageManager = new DocStorageManagerImpl()