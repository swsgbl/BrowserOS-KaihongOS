import { IWebviewController } from '../common/IWebviewController'
import { TabInfo } from '../model/TabInfo'
import { TabStatus } from '../common/Types'
import { EventBus, EventBusEvents } from '../infra/EventBus'
import { ErrorHandler, AppError } from '../infra/ErrorHandler'
import { ErrorCodes } from '../common/ErrorCodes'
import { Constants } from '../common/Constants'


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
    return tab
  }

  createAgentTab(agentId: string): TabInfo {
    const tabId = this.generateTabId()
    const tab = new TabInfo(tabId, agentId, false)
    tab.title = 'Agent ' + agentId.substring(agentId.length - 6)
    this.tabs.set(tabId, tab)
    // P3 修复：agent tab 立即可见于标签栏（BrowserShell 监听 TAB_STATUS_CHANGE 刷新）
    EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, tab.toJSON())
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

  private generateTabId(): string {
    return `tab_${++this.tabCounter}_${Date.now()}`
  }
}

export const TabManager = new TabManagerImpl()