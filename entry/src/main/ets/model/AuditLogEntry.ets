interface AuditLogEntryJSON {
  requestId: string
  agentId: string
  operationType: string
  targetUrl: string
  timestamp: number
  result: string
  errorMessage: string
  durationMs: number
}

export class AuditLogEntry {
  requestId: string = ''
  agentId: string = ''
  operationType: string = ''
  targetUrl: string = ''
  timestamp: number = 0
  result: string = ''
  errorMessage: string = ''
  durationMs: number = 0

  constructor(requestId: string, agentId: string, operationType: string, targetUrl: string) {
    this.requestId = requestId
    this.agentId = agentId
    this.operationType = operationType
    this.targetUrl = targetUrl
    this.timestamp = Date.now()
  }

  setResult(result: string, errorMessage: string = '', durationMs: number = 0): void {
    this.result = result
    this.errorMessage = errorMessage
    this.durationMs = durationMs
  }

  toJSON(): AuditLogEntryJSON {
    const result: AuditLogEntryJSON = {
      requestId: this.requestId,
      agentId: this.agentId,
      operationType: this.operationType,
      targetUrl: this.targetUrl,
      timestamp: this.timestamp,
      result: this.result,
      errorMessage: this.errorMessage,
      durationMs: this.durationMs
    }
    return result
  }

  static fromJSON(json: Record<string, Object>): AuditLogEntry {
    const entry = new AuditLogEntry(
      json['requestId'] as string,
      json['agentId'] as string,
      json['operationType'] as string,
      json['targetUrl'] as string
    )
    entry.timestamp = json['timestamp'] as number
    entry.result = json['result'] as string
    entry.errorMessage = json['errorMessage'] as string
    entry.durationMs = json['durationMs'] as number
    return entry
  }

  toLogString(): string {
    return JSON.stringify(this.toJSON())
  }
}