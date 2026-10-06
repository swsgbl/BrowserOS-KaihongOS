import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'

export interface HistoryEntry {
  url: string
  title: string
  timestamp: number
}

class HistoryManagerImpl {
  private navigationStacks: Map<string, HistoryEntry[]> = new Map()
  private currentIndices: Map<string, number> = new Map()

  initStack(tabId: string): void {
    if (!this.navigationStacks.has(tabId)) {
      this.navigationStacks.set(tabId, [])
      this.currentIndices.set(tabId, -1)
    }
  }

  recordNavigation(tabId: string, url: string, title: string = ''): void {
    this.initStack(tabId)
    const stack = this.navigationStacks.get(tabId)!
    const currentIndex = this.currentIndices.get(tabId)!

    if (currentIndex < stack.length - 1) {
      stack.splice(currentIndex + 1)
    }

    const entry: HistoryEntry = { url: url, title: title, timestamp: Date.now() }
    stack.push(entry)
    this.currentIndices.set(tabId, stack.length - 1)
  }

  canGoBack(tabId: string): boolean {
    const idx = this.currentIndices.get(tabId) ?? -1
    return idx > 0
  }

  canGoForward(tabId: string): boolean {
    const stack = this.navigationStacks.get(tabId)
    const idx = this.currentIndices.get(tabId) ?? -1
    return stack !== undefined && idx < stack.length - 1
  }

  getBackUrl(tabId: string): string | null {
    const idx = this.currentIndices.get(tabId) ?? -1
    const stack = this.navigationStacks.get(tabId)
    if (stack && idx > 0) {
      this.currentIndices.set(tabId, idx - 1)
      return stack[idx - 1].url
    }
    return null
  }

  getForwardUrl(tabId: string): string | null {
    const idx = this.currentIndices.get(tabId) ?? -1
    const stack = this.navigationStacks.get(tabId)
    if (stack && idx < stack.length - 1) {
      this.currentIndices.set(tabId, idx + 1)
      return stack[idx + 1].url
    }
    return null
  }

  getCurrentUrl(tabId: string): string | null {
    const idx = this.currentIndices.get(tabId) ?? -1
    const stack = this.navigationStacks.get(tabId)
    if (stack && idx >= 0 && idx < stack.length) {
      return stack[idx].url
    }
    return null
  }

  getHistory(tabId: string): HistoryEntry[] {
    return this.navigationStacks.get(tabId) || []
  }

  /** P5: 跨 tab 汇总最近历史（时间倒序，供历史面板使用） */
  getAllHistory(limit: number): HistoryEntry[] {
    const all: HistoryEntry[] = []
    this.navigationStacks.forEach((stack: HistoryEntry[]) => {
      for (const entry of stack) {
        all.push(entry)
      }
    })
    all.sort((a: HistoryEntry, b: HistoryEntry) => b.timestamp - a.timestamp)
    if (all.length > limit) {
      return all.slice(0, limit)
    }
    return all
  }

  clearHistory(tabId: string): void {
    this.navigationStacks.delete(tabId)
    this.currentIndices.delete(tabId)
  }

  removeStack(tabId: string): void {
    this.clearHistory(tabId)
  }

  async persistHistory(): Promise<void> {
    const data: Record<string, Object> = {}
    this.navigationStacks.forEach((stack: HistoryEntry[], tabId: string) => {
      data[tabId] = stack
    })
    await StorageManager.saveJSON('tabs/history.json', data)
  }

  async loadHistory(): Promise<void> {
    const json = await StorageManager.loadJSON('tabs/history.json')
    if (json) {
      for (const key of Object.keys(json)) {
        const stack = json[key] as HistoryEntry[]
        this.navigationStacks.set(key, stack)
        this.currentIndices.set(key, stack.length - 1)
      }
    }
  }
}

export const HistoryManager = new HistoryManagerImpl()
