import { LoginStateData, CookieEntry } from '../model/LoginStateData'
import { SecureStorageAdapter } from '../storage/SecureStorageAdapter'
import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'

interface LoginStateImportedData {
  domains: string[]
  count: number
}

class LoginStateManagerImpl {
  private importedDomains: Set<string> = new Set()
  private loginStates: Map<string, LoginStateData> = new Map()

  async importFromChrome(): Promise<LoginStateData[]> {
    try {
      const chromeDataPath = this.detectChromeDataPath()
      if (!chromeDataPath) {
        ErrorHandler.handle(new AppError(ErrorCodes.LGN_001, 'Chrome not detected'))
        return []
      }

      const cookies = await this.readChromeCookies(chromeDataPath)
      const localStorage = await this.readChromeLocalStorage(chromeDataPath)

      const domainMap: Map<string, LoginStateData> = new Map()

      for (const cookie of cookies) {
        if (!domainMap.has(cookie.domain)) {
          domainMap.set(cookie.domain, new LoginStateData(cookie.domain))
        }
        domainMap.get(cookie.domain)!.addCookie(cookie)
      }

      localStorage.forEach((storage: Record<string, string>, domain: string) => {
        if (!domainMap.has(domain)) {
          domainMap.set(domain, new LoginStateData(domain))
        }
        const state = domainMap.get(domain)!
        const storageKeys = Object.keys(storage)
        for (const key of storageKeys) {
          state.setLocalStorageItem(key, storage[key])
        }
      })

      const results: LoginStateData[] = []
      const domainEntries = Array.from(domainMap.entries())
      for (const entry of domainEntries) {
        const domain = entry[0]
        const state = entry[1]
        state.isEncrypted = SecureStorageAdapter.isSecureStorageAvailable()
        await this.persistLoginState(state)
        this.importedDomains.add(domain)
        this.loginStates.set(domain, state)
        results.push(state)
      }

      const importedData: LoginStateImportedData = {
        domains: Array.from(this.importedDomains),
        count: results.length
      }
      EventBus.emit(EventBusEvents.LOGIN_STATE_IMPORTED, importedData)

      return results
    } catch (e) {
      ErrorHandler.handle(new AppError(ErrorCodes.LGN_002, `Chrome data format incompatible: ${e}`))
      return []
    }
  }

  async importSelected(domains: string[]): Promise<LoginStateData[]> {
    const allStates = await this.importFromChrome()
    return allStates.filter(state => domains.includes(state.domain))
  }

  getImportedDomains(): string[] {
    return Array.from(this.importedDomains)
  }

  getLoginState(domain: string): LoginStateData | null {
    return this.loginStates.get(domain) || null
  }

  applyLoginState(domain: string): LoginStateData | null {
    return this.loginStates.get(domain) || null
  }

  async clearAll(): Promise<boolean> {
    this.importedDomains.clear()
    this.loginStates.clear()

    const files = await StorageManager.listDir('login_state')
    for (const file of files) {
      await StorageManager.delete(`login_state/${file}`)
    }
    return true
  }

  isSecureStorageAvailable(): boolean {
    return SecureStorageAdapter.isSecureStorageAvailable()
  }

  private detectChromeDataPath(): string | null {
    return null
  }

  private async readChromeCookies(chromeDataPath: string): Promise<CookieEntry[]> {
    return []
  }

  private async readChromeLocalStorage(chromeDataPath: string): Promise<Map<string, Record<string, string>>> {
    return new Map()
  }

  private async persistLoginState(state: LoginStateData): Promise<boolean> {
    const filePath = `login_state/${state.domain}.json`
    if (SecureStorageAdapter.isSecureStorageAvailable()) {
      return SecureStorageAdapter.encryptStoreJSON(filePath, state.toJSON())
    } else {
      return StorageManager.saveJSON(filePath, state.toJSON())
    }
  }

  async loadPersistedStates(): Promise<void> {
    const files = await StorageManager.listDir('login_state')
    for (const file of files) {
      const domain = file.replace('.json', '')
      let json: Record<string, Object> | null = null

      if (SecureStorageAdapter.isSecureStorageAvailable()) {
        json = await SecureStorageAdapter.decryptLoadJSON(`login_state/${file}`)
      } else {
        json = await StorageManager.loadJSON(`login_state/${file}`)
      }

      if (json) {
        try {
          const state = LoginStateData.fromJSON(json)
          this.loginStates.set(domain, state)
          this.importedDomains.add(domain)
        } catch (e) {
          console.error(`Failed to load login state for ${domain}: ${e}`)
        }
      }
    }
  }
}

export const LoginStateManager = new LoginStateManagerImpl()