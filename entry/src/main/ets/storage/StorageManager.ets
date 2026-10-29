import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
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

  /** P3: 暴露基路径（token 外显等沙盒文件绝对路径留痕用） */
  getBasePath(): string {
    return this.basePath
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
      const decoder = util.TextDecoder.create('utf-8')
      return decoder.decodeWithStream(new Uint8Array(buffer))
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

  /** P69: 同步读 JSON（启动链非 async 上下文用；失败返 null） */
  getSync(relativePath: string): Record<string, Object> | null {
    try {
      const fullPath = `${this.basePath}/${relativePath}`
      const stat = fs.statSync(fullPath)
      const file = fs.openSync(fullPath, fs.OpenMode.READ_ONLY)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      const decoder = util.TextDecoder.create('utf-8')
      const text = decoder.decodeWithStream(new Uint8Array(buffer))
      return JSON.parse(text) as Record<string, Object>
    } catch (e) {
      return null
    }
  }

  /** P69: 同步写 JSON（小状态文件；fire-and-forget 语义） */
  saveJSONSync(relativePath: string, data: Object): boolean {
    try {
      const fullPath = `${this.basePath}/${relativePath}`
      const dirPath = fullPath.substring(0, fullPath.lastIndexOf('/'))
      try {
        fs.mkdirSync(dirPath, true)
      } catch (e) {
      }
      const file = fs.openSync(fullPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, JSON.stringify(data))
      fs.closeSync(file)
      return true
    } catch (e) {
      return false
    }
  }
}

export const StorageManager = new StorageManagerImpl()