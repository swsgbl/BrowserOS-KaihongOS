interface OperationLogJSON {
  operationType: string
  targetElement: string
  timestamp: number
  result: string
  detail: string
}

export class OperationLog {
  operationType: string = ''
  targetElement: string = ''
  timestamp: number = 0
  result: string = ''
  detail: string = ''

  constructor(operationType: string, targetElement: string, result: string, detail: string = '') {
    this.operationType = operationType
    this.targetElement = targetElement
    this.result = result
    this.detail = detail
    this.timestamp = Date.now()
  }

  toJSON(): OperationLogJSON {
    const result: OperationLogJSON = {
      operationType: this.operationType,
      targetElement: this.targetElement,
      timestamp: this.timestamp,
      result: this.result,
      detail: this.detail
    }
    return result
  }

  static fromJSON(json: Record<string, Object>): OperationLog {
    const log = new OperationLog(
      json['operationType'] as string,
      json['targetElement'] as string,
      json['result'] as string,
      json['detail'] as string
    )
    log.timestamp = json['timestamp'] as number
    return log
  }
}

interface ScreenshotEntryJSON {
  timestamp: number
  base64Data: string
  url: string
}

export class ScreenshotEntry {
  timestamp: number = 0
  base64Data: string = ''
  url: string = ''

  constructor(base64Data: string, url: string) {
    this.base64Data = base64Data
    this.url = url
    this.timestamp = Date.now()
  }

  toJSON(): ScreenshotEntryJSON {
    const result: ScreenshotEntryJSON = {
      timestamp: this.timestamp,
      base64Data: this.base64Data,
      url: this.url
    }
    return result
  }

  static fromJSON(json: Record<string, Object>): ScreenshotEntry {
    const entry = new ScreenshotEntry(
      json['base64Data'] as string,
      json['url'] as string
    )
    entry.timestamp = json['timestamp'] as number
    return entry
  }
}

interface SessionRecordJSON {
  sessionId: string
  agentId: string
  startTime: number
  endTime: number
  duration: number
  urlSequence: string[]
  filePath: string
  fileSize: number
  operationLogs: OperationLogJSON[]
  screenshots: ScreenshotEntryJSON[]
  isCorrupted: boolean
}

export class SessionRecord {
  sessionId: string = ''
  agentId: string = ''
  startTime: number = 0
  endTime: number = 0
  duration: number = 0
  urlSequence: string[] = []
  filePath: string = ''
  fileSize: number = 0
  operationLogs: OperationLog[] = []
  screenshots: ScreenshotEntry[] = []
  isCorrupted: boolean = false

  constructor(sessionId: string, agentId: string) {
    this.sessionId = sessionId
    this.agentId = agentId
    this.startTime = Date.now()
  }

  endSession(): void {
    this.endTime = Date.now()
    this.duration = this.endTime - this.startTime
  }

  addUrl(url: string): void {
    this.urlSequence.push(url)
  }

  addOperationLog(log: OperationLog): void {
    this.operationLogs.push(log)
  }

  addScreenshot(screenshot: ScreenshotEntry): void {
    this.screenshots.push(screenshot)
  }

  toJSON(): SessionRecordJSON {
    const result: SessionRecordJSON = {
      sessionId: this.sessionId,
      agentId: this.agentId,
      startTime: this.startTime,
      endTime: this.endTime,
      duration: this.duration,
      urlSequence: this.urlSequence,
      filePath: this.filePath,
      fileSize: this.fileSize,
      operationLogs: this.operationLogs.map((log: OperationLog): OperationLogJSON => log.toJSON()),
      screenshots: this.screenshots.map((shot: ScreenshotEntry): ScreenshotEntryJSON => shot.toJSON()),
      isCorrupted: this.isCorrupted
    }
    return result
  }

  static fromJSON(json: Record<string, Object>): SessionRecord {
    const record = new SessionRecord(
      json['sessionId'] as string,
      json['agentId'] as string
    )
    record.startTime = json['startTime'] as number
    record.endTime = json['endTime'] as number
    record.duration = json['duration'] as number
    record.urlSequence = json['urlSequence'] as string[]
    record.filePath = json['filePath'] as string
    record.fileSize = json['fileSize'] as number
    record.isCorrupted = json['isCorrupted'] as boolean
    const logs = json['operationLogs'] as Object[] | undefined
    if (logs) {
      for (const item of logs) {
        record.operationLogs.push(OperationLog.fromJSON(item as Record<string, Object>))
      }
    }
    const shots = json['screenshots'] as Object[] | undefined
    if (shots) {
      for (const item of shots) {
        record.screenshots.push(ScreenshotEntry.fromJSON(item as Record<string, Object>))
      }
    }
    return record
  }
}