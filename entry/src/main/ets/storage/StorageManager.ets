import { fileIo as fs } from '@kit.CoreFileKit'
import { Constants } from '../common/Constants'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'

interface StorageErrorContext {
  path: string
}

class StorageManagerImpl {
  private basePath: string = Constants.STORAGE_BASE_PATH

  setBasePath(path: string): void {
    this.basePath = path
  }

  async save(relativePath: string, data: string): Promise<boolean> {
    try {
      const fullPath = `${this.basePath}/${relativePath}`
      const dirPath = fullPath.substring(0, fullPath.lastIndexOf('/'))
      try {
        fs.mkdirSync(dirPath, true)
      } catch (e) {
      }
      const file = fs.openSync(fullPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, data)
      fs.closeSync(file)
      return true
    } catch (e) {
      const errorContext: StorageErrorContext = { path: relativePath }
      ErrorHandler.handle(new AppError(ErrorCodes.STG_002, `Save failed: ${e}`, errorContext))
      return false
    }
  }

  async load(relativePath: string): Promise<string | null> {
    try {
      const fullPath = `${this.basePath}/${relativePath}`
      const file = fs.openSync(fullPath, fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(fullPath)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      const view = new Uint8Array(buffer)
      let result = ''
      for (let i = 0; i < view.length; i++) {
        result += String.fromCharCode(view[i])
      }
      return result
    } catch (e) {
      return null
    }
  }

  async delete(relativePath: string): Promise<boolean> {
    try {
      const fullPath = `${this.basePath}/${relativePath}`
      fs.unlinkSync(fullPath)
      return true
    } catch (e) {
      return false
    }
  }

  async checkSpace(): Promise<number> {
    try {
      const stat = fs.statSync(this.basePath)
      return stat.size
    } catch (e) {
      return 0
    }
  }

  async exists(relativePath: string): Promise<boolean> {
    try {
      const fullPath = `${this.basePath}/${relativePath}`
      fs.accessSync(fullPath)
      return true
    } catch (e) {
      return false
    }
  }

  async listDir(relativePath: string): Promise<string[]> {
    try {
      const fullPath = `${this.basePath}/${relativePath}`
      const entries = fs.listFileSync(fullPath)
      return entries
    } catch (e) {
      return []
    }
  }

  async saveJSON(relativePath: string, data: Object): Promise<boolean> {
    return this.save(relativePath, JSON.stringify(data))
  }

  async loadJSON(relativePath: string): Promise<Record<string, Object> | null> {
    const content = await this.load(relativePath)
    if (content) {
      try {
        return JSON.parse(content) as Record<string, Object>
      } catch (e) {
        return null
      }
    }
    return null
  }
}

export const StorageManager = new StorageManagerImpl()