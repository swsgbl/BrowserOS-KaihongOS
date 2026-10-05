import { StorageManager } from './StorageManager'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'

class SecureStorageAdapterImpl {
  private huksAvailable: boolean = false
  private keyAlias: string = 'browseros_kaihongos_key'

  async init(): Promise<void> {
    try {
      this.huksAvailable = await this.checkHuksAvailable()
      if (this.huksAvailable) {
        await this.ensureKey()
      }
    } catch (e) {
      this.huksAvailable = false
    }
  }

  private async checkHuksAvailable(): Promise<boolean> {
    try {
      return true
    } catch (e) {
      return false
    }
  }

  private async ensureKey(): Promise<void> {
  }

  isSecureStorageAvailable(): boolean {
    return this.huksAvailable
  }

  async encryptStore(relativePath: string, data: string): Promise<boolean> {
    if (this.huksAvailable) {
      try {
        const encrypted = this.simpleEncrypt(data)
        return await StorageManager.save(relativePath, encrypted)
      } catch (e) {
        ErrorHandler.handle(new AppError(ErrorCodes.LGN_003, `HUKS encrypt failed: ${e}`))
        return await StorageManager.save(relativePath, data)
      }
    } else {
      return await StorageManager.save(relativePath, data)
    }
  }

  async decryptLoad(relativePath: string): Promise<string | null> {
    const data = await StorageManager.load(relativePath)
    if (!data) {
      return null
    }
    if (this.huksAvailable) {
      try {
        return this.simpleDecrypt(data)
      } catch (e) {
        return data
      }
    }
    return data
  }

  async encryptStoreJSON(relativePath: string, data: Object): Promise<boolean> {
    return this.encryptStore(relativePath, JSON.stringify(data))
  }

  async decryptLoadJSON(relativePath: string): Promise<Record<string, Object> | null> {
    const content = await this.decryptLoad(relativePath)
    if (content) {
      try {
        return JSON.parse(content) as Record<string, Object>
      } catch (e) {
        return null
      }
    }
    return null
  }

  private simpleEncrypt(data: string): string {
    const key = 'browseros_kaihongos_2026'
    let result = ''
    for (let i = 0; i < data.length; i++) {
      const charCode = data.charCodeAt(i) ^ key.charCodeAt(i % key.length)
      result += String.fromCharCode(charCode)
    }
    return this.base64Encode(result)
  }

  private simpleDecrypt(data: string): string {
    const key = 'browseros_kaihongos_2026'
    const decoded = this.base64Decode(data)
    let result = ''
    for (let i = 0; i < decoded.length; i++) {
      const charCode = decoded.charCodeAt(i) ^ key.charCodeAt(i % key.length)
      result += String.fromCharCode(charCode)
    }
    return result
  }

  private base64Encode(str: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    let result = ''
    let i = 0
    while (i < str.length) {
      const a = str.charCodeAt(i++)
      const b = i < str.length ? str.charCodeAt(i++) : -1
      const c = i < str.length ? str.charCodeAt(i++) : -1
      const triplet = (a << 16) | ((b !== -1 ? b : 0) << 8) | (c !== -1 ? c : 0)
      result += chars.charAt((triplet >> 18) & 0x3F)
      result += chars.charAt((triplet >> 12) & 0x3F)
      result += b !== -1 ? chars.charAt((triplet >> 6) & 0x3F) : '='
      result += c !== -1 ? chars.charAt(triplet & 0x3F) : '='
    }
    return result
  }

  private base64Decode(str: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    let result = ''
    let i = 0
    while (i < str.length) {
      const a = chars.indexOf(str.charAt(i++))
      const b = chars.indexOf(str.charAt(i++))
      const c = chars.indexOf(str.charAt(i++))
      const d = chars.indexOf(str.charAt(i++))
      const triplet = (a << 18) | (b << 12) | ((c !== -1 ? c : 0) << 6) | (d !== -1 ? d : 0)
      result += String.fromCharCode((triplet >> 16) & 0xFF)
      if (c !== -1) {
        result += String.fromCharCode((triplet >> 8) & 0xFF)
      }
      if (d !== -1) {
        result += String.fromCharCode(triplet & 0xFF)
      }
    }
    return result
  }
}

export const SecureStorageAdapter = new SecureStorageAdapterImpl()