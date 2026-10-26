/**
 * P47-A: DevTools 数据收集器 —— 按标签收集 Console 日志 / Network 请求
 * BrowserShell 的 onConsole / onInterceptRequest 写入，DevToolsPage 读取展示。
 * 模块级单例（项目惯例，避开 arkts-no-standalone-this）
 */

export enum DtLogLevel {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4
}

export interface ConsoleLogEntry {
  ts: number
  level: number
  source: string
  message: string
}

export interface NetworkEntry {
  ts: number
  url: string
  method: string
  headers: string
  durationMs: number
}

class DevToolsCollectorImpl {
  private consoleLogs: Map<string, ConsoleLogEntry[]> = new Map()
  private networkLogs: Map<string, NetworkEntry[]> = new Map()
  private readonly MAX_LOGS = 500

  addConsole(tabId: string, level: number, source: string, message: string): void {
    let arr = this.consoleLogs.get(tabId)
    if (!arr) {
      arr = []
      this.consoleLogs.set(tabId, arr)
    }
    arr.push({ ts: Date.now(), level: level, source: source, message: message })
    if (arr.length > this.MAX_LOGS) {
      arr.splice(0, arr.length - this.MAX_LOGS)
    }
  }

  getConsole(tabId: string): ConsoleLogEntry[] {
    return this.consoleLogs.get(tabId) ?? []
  }

  clearConsole(tabId: string): void {
    this.consoleLogs.set(tabId, [])
  }

  addNetwork(tabId: string, url: string, method: string, headers: string): void {
    let arr = this.networkLogs.get(tabId)
    if (!arr) {
      arr = []
      this.networkLogs.set(tabId, arr)
    }
    arr.push({ ts: Date.now(), url: url, method: method, headers: headers, durationMs: 0 })
    if (arr.length > this.MAX_LOGS) {
      arr.splice(0, arr.length - this.MAX_LOGS)
    }
  }

  getNetwork(tabId: string): NetworkEntry[] {
    return this.networkLogs.get(tabId) ?? []
  }

  clearNetwork(tabId: string): void {
    this.networkLogs.set(tabId, [])
  }

  clearAll(tabId: string): void {
    this.consoleLogs.delete(tabId)
    this.networkLogs.delete(tabId)
  }
}

export const DevToolsCollector = new DevToolsCollectorImpl()
