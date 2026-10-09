import { IWebviewController } from '../common/IWebviewController'
import { TabInfo } from '../model/TabInfo'
import { TabStatus } from '../common/Types'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'

interface PersistTab {
  id: string
  title: string
  url: string
  isDashboard: boolean
  agentId: string
}

interface RestoreUrlEntry {
  tabId: string
  url: string
}


interface WebViewInstance {
  tabId: string
  controller: IWebviewController
  storagePartition: string
}

interface TabClosedEvent {
  tabId: string
  action: string
}

class TabManagerImpl {
  private tabs: Map<string, TabInfo> = new Map()
  private webviews: Map<string, WebViewInstance> = new Map()
  private activeTabId: string = ''
  private tabCounter: number = 0
  private static PREFS_CTX: common.UIAbilityContext | null = null
  private restoreUrls: RestoreUrlEntry[] = []

  createTab(isDashboard: boolean = false): TabInfo {
    const tabId = this.generateTabId()
    const tab = new TabInfo(tabId, '', isDashboard)

    if (isDashboard) {
      tab.title = 'Dashboard'
    }

    this.tabs.set(tabId, tab)
    if (!this.activeTabId) {
      this.activeTabId = tabId
    }

    EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, tab.toJSON())
    this.schedulePersist()
    return tab
  }

  createAgentTab(agentId: string): TabInfo {
    const tabId = this.generateTabId()
    const tab = new TabInfo(tabId, agentId, false)
    tab.title = 'Agent ' + agentId.substring(agentId.length - 6)
    this.tabs.set(tabId, tab)
    // P3 修复：agent tab 立即可见于标签栏（BrowserShell 监听 TAB_STATUS_CHANGE 刷新）
    EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, tab.toJSON())
    this.schedulePersist()
    return tab
  }

  switchTab(tabId: string): boolean {
    if (!this.tabs.has(tabId)) {
      ErrorHandler.handle(new AppError(ErrorCodes.TAB_002, `Tab not found: ${tabId}`))
      return false
    }
    this.activeTabId = tabId
    const tab = this.tabs.get(tabId)!
    EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, tab.toJSON())
    this.schedulePersist()
    return true
  }

  closeTab(tabId: string): boolean {
    if (!this.tabs.has(tabId)) {
      return false
    }
    this.tabs.delete(tabId)
    this.webviews.delete(tabId)

    if (this.activeTabId === tabId) {
      const remaining = Array.from(this.tabs.keys())
      this.activeTabId = remaining.length > 0 ? remaining[0] : ''
    }

    const closeData: TabClosedEvent = { tabId: tabId, action: 'closed' }
    EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, closeData)
    this.schedulePersist()
    return true
  }

  getTab(tabId: string): TabInfo | null {
    return this.tabs.get(tabId) || null
  }

  getAllTabs(): TabInfo[] {
    return Array.from(this.tabs.values())
  }

  getActiveTabId(): string {
    return this.activeTabId
  }

  updateTabUrl(tabId: string, url: string): void {
    const tab = this.tabs.get(tabId)
    if (tab) {
      tab.currentUrl = url
      tab.status = TabStatus.IDLE
      EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, tab.toJSON())
    }
  }

  updateTabTitle(tabId: string, title: string): void {
    const tab = this.tabs.get(tabId)
    if (tab) {
      tab.title = title
      EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, tab.toJSON())
    }
  }

  updateTabStatus(tabId: string, status: TabStatus): void {
    const tab = this.tabs.get(tabId)
    if (tab) {
      tab.status = status
      EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, tab.toJSON())
    }
  }

  registerWebView(tabId: string, controller: IWebviewController, storagePartition: string): void {
    this.webviews.set(tabId, {
      tabId,
      controller,
      storagePartition
    })
  }

  getWebView(tabId: string): WebViewInstance | null {
    return this.webviews.get(tabId) || null
  }

  getTabCount(): number {
    return this.tabs.size
  }

  // ---------- P16b: 标签持久化（Preferences tabs_state，节流 500ms） ----------

  private static readonly STORE_NAME: string = 'tabs_state'
  private static readonly KEY_TABS: string = 'tabs'
  private static readonly MAX_RESTORE: number = 8
  private prefsInstance: preferences.Preferences | null = null
  private persistTimer: number = -1

  private ensurePrefs(): preferences.Preferences | null {
    if (this.prefsInstance) {
      return this.prefsInstance
    }
    if (!TabManagerImpl.PREFS_CTX) {
      console.error('[TabManager] prefs context not set, persistence disabled')
      return null
    }
    try {
      this.prefsInstance = preferences.getPreferencesSync(TabManagerImpl.PREFS_CTX, { name: TabManagerImpl.STORE_NAME })
      return this.prefsInstance
    } catch (e) {
      console.error('[TabManager] getPreferencesSync error: ' + e)
      return null
    }
  }

  /** P16b: EntryAbility 早期调用，注入 context 供 Preferences 使用 */
  setContext(ctx: common.UIAbilityContext): void {
    TabManagerImpl.PREFS_CTX = ctx
    console.info('[TabManager] context set for tabs_state persistence')
  }

  /** 持久化当前标签（顺序保持；dashboard 排最前；总上限 8）；节流 500ms 后落盘 */
  persistTabs(): void {
    const p: preferences.Preferences | null = this.ensurePrefs()
    if (!p) {
      return
    }
    try {
      const dash: PersistTab[] = []
      const normal: PersistTab[] = []
      this.tabs.forEach((tab: TabInfo) => {
        const item: PersistTab = {
          id: tab.tabId,
          title: tab.title,
          url: tab.currentUrl,
          isDashboard: tab.isDashboard,
          agentId: tab.agentId
        }
        if (tab.isDashboard) {
          dash.push(item)
        } else {
          normal.push(item)
        }
      })
      const all = dash.concat(normal.slice(0, TabManagerImpl.MAX_RESTORE))
      p.putSync(TabManagerImpl.KEY_TABS, JSON.stringify(all))
      p.flush()
      console.info('[TabManager] persisted ' + all.length + ' tabs')
    } catch (e) {
      console.error('[TabManager] persistTabs error: ' + e)
    }
  }

  /** 节流版 persist（create/switch/close 后调用） */
  private schedulePersist(): void {
    if (this.persistTimer >= 0) {
      clearTimeout(this.persistTimer)
    }
    this.persistTimer = setTimeout(() => {
      this.persistTimer = -1
      this.persistTabs()
    }, 500)
  }

  /** 冷启动恢复：dashboard 标签永远第一个；非 dashboard 重建后 URL 由 takeRestoreUrls 补载 */
  restoreTabs(): number {
    if (this.tabs.size > 0) {
      return 0
    }
    const p: preferences.Preferences | null = this.ensurePrefs()
    if (!p) {
      return 0
    }
    try {
      const raw = p.getSync(TabManagerImpl.KEY_TABS, '[]') as string
      const arr: PersistTab[] = JSON.parse(raw) as PersistTab[]
      if (!Array.isArray(arr) || arr.length === 0) {
        return 0
      }
      const valid = arr.filter((x: PersistTab): boolean =>
        x !== null && x.id !== undefined && x.id.length > 0).slice(0, TabManagerImpl.MAX_RESTORE)
      if (valid.length === 0) {
        return 0
      }
      this.tabs.clear()
      this.webviews.clear()
      this.activeTabId = ''
      let restored = 0
      for (const item of valid) {
        let idToUse = item.id
        while (this.tabs.has(idToUse)) {
          idToUse = this.generateTabId()
        }
        const tab = new TabInfo(idToUse, item.agentId ? item.agentId : '', !!item.isDashboard)
        tab.title = item.title ? item.title : (item.isDashboard ? 'Dashboard' : '')
        tab.currentUrl = item.url ? item.url : ''
        this.tabs.set(idToUse, tab)
        if (!this.activeTabId) {
          this.activeTabId = idToUse
        }
        restored++
      }
      this.tabs.forEach((tab: TabInfo) => {
        if (!tab.isDashboard && tab.currentUrl.length > 0) {
          this.restoreUrls.push({ tabId: tab.tabId, url: tab.currentUrl })
        }
      })
      console.info('[TabManager] restoreTabs: ' + restored + ' tabs, pendingUrls=' + this.restoreUrls.length)
      return restored
    } catch (e) {
      console.error('[TabManager] restoreTabs error: ' + e)
      return 0
    }
  }

  /** P16b: 取走待恢复 URL（BrowserShell aboutToAppear 消费 → pendingUrl 机制补载） */
  takeRestoreUrls(): RestoreUrlEntry[] {
    const out = this.restoreUrls.slice()
    this.restoreUrls = []
    return out
  }

  private generateTabId(): string {
    return `tab_${++this.tabCounter}_${Date.now()}`
  }
}

export const TabManager = new TabManagerImpl()