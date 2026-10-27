// P51 part4: AuditLogEntry paramsRedacted + MCPServer fills it via redactDeep + SessionRecord/OperationLog sweep
const fs = require('fs')

function repFile(file, pairs) {
  let s = fs.readFileSync(file, 'utf8')
  const D = s.includes('\r\n') ? '\r\n' : '\n'
  for (const [o, n, tag] of pairs) {
    const oo = o.split('\n').join(D), nn = n.split('\n').join(D)
    if (s.includes(nn)) { console.log('skip: ' + tag); continue }
    if (!s.includes(oo)) { console.error('MISS [' + file + ']: ' + tag); process.exit(1) }
    s = s.replace(oo, nn)
    console.log('ok [' + file.split('/').pop() + ']: ' + tag)
  }
  fs.writeFileSync(file, s, 'utf8')
}

// AuditLogEntry: add paramsRedacted field
repFile('entry/src/main/ets/model/AuditLogEntry.ets', [
  [
    'interface AuditLogEntryJSON {\n  requestId: string\n  agentId: string\n  operationType: string\n  targetUrl: string\n  timestamp: number\n  result: string\n  errorMessage: string\n  durationMs: number\n}',
    'interface AuditLogEntryJSON {\n  requestId: string\n  agentId: string\n  operationType: string\n  targetUrl: string\n  timestamp: number\n  result: string\n  errorMessage: string\n  durationMs: number\n  paramsRedacted: string\n}'
  ],
  [
    '  errorMessage: string = \'\'\n  durationMs: number = 0',
    '  errorMessage: string = \'\'\n  durationMs: number = 0\n  /** P51 (1c): 工具参数（deep-redacted 后序列化；\'\'=未记录） */\n  paramsRedacted: string = \'\''
  ],
  [
    '      errorMessage: this.errorMessage,\n      durationMs: this.durationMs\n    }\n    return result',
    '      errorMessage: this.errorMessage,\n      durationMs: this.durationMs,\n      paramsRedacted: this.paramsRedacted\n    }\n    return result'
  ],
  [
    '    entry.durationMs = json[\'durationMs\'] as number\n    return entry',
    '    entry.durationMs = json[\'durationMs\'] as number\n    entry.paramsRedacted = (json[\'paramsRedacted\'] as string) || \'\'\n    return entry'
  ]
])

// MCPServer: fill paramsRedacted via redactDeep at audit-entry creation
repFile('entry/src/main/ets/service/MCPServer.ets', [
  [
    "import { McpSessionStore } from './McpSessionStore'",
    "import { McpSessionStore } from './McpSessionStore'\nimport { redactDeep } from './AuditRedactor'"
  ],
  [
    "    const auditEntry = new AuditLogEntry(requestId, agentId, canonical, params['url'] as string || '')",
    "    const auditEntry = new AuditLogEntry(requestId, agentId, canonical, params['url'] as string || '')\n    // P51 (1c): 参数深度脱敏后入审计（type \"mypassword123\" -> text 前 8 字符 + ***）\n    try {\n      auditEntry.paramsRedacted = JSON.stringify(redactDeep(params))\n    } catch (e) {\n      auditEntry.paramsRedacted = ''\n    }"
  ]
])

console.log('part4 done')
