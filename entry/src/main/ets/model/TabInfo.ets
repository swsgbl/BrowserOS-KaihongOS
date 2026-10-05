import { TabStatus } from '../common/Types'

interface TabInfoJSON {
  tabId: string
  agentId: string
  currentUrl: string
  title: string
  status: TabStatus
  isDashboard: boolean
  createdAt: number
}

export class TabInfo {
  tabId: string = ''
  agentId: string = ''
  currentUrl: string = ''
  title: string = ''
  status: TabStatus = TabStatus.IDLE
  isDashboard: boolean = false
  createdAt: number = 0

  constructor(tabId: string, agentId: string, isDashboard: boolean = false) {
    this.tabId = tabId
    this.agentId = agentId
    this.isDashboard = isDashboard
    this.createdAt = Date.now()
    this.status = TabStatus.IDLE
  }

  toJSON(): TabInfoJSON {
    const result: TabInfoJSON = {
      tabId: this.tabId,
      agentId: this.agentId,
      currentUrl: this.currentUrl,
      title: this.title,
      status: this.status,
      isDashboard: this.isDashboard,
      createdAt: this.createdAt
    }
    return result
  }

  static fromJSON(json: TabInfoJSON): TabInfo {
    const tab = new TabInfo(
      json.tabId,
      json.agentId,
      json.isDashboard
    )
    tab.currentUrl = json.currentUrl
    tab.title = json.title
    tab.status = json.status
    tab.createdAt = json.createdAt
    return tab
  }
}