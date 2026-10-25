// P42 补丁脚本：MCPServer(B/CSPRNG+C/type gate) HttpMcpTransport(A) WsMcpTransport(A)
//   McpJsonRpcCore(D) AuditLogger(D) SessionManager(E) BrowserShell(G) EntryAbility 注释
// CRLF 混合行尾 → 统一按 \n split/join，行级替换，writeFileSync 时保留原 \n（无 \r）
const fs = require('fs')
const path = require('path')
const ROOT = 'D:/BrowserOS - KaihongOS'
let edits = 0

function load(rel) {
  const p = path.join(ROOT, rel)
  const raw = fs.readFileSync(p, 'utf8')
  return { p, lines: raw.split(/\r?\n/) }
}
function save(ctx) {
  fs.writeFileSync(ctx.p, ctx.lines.join('\n'), 'utf8')
}
// 在 lines 中找包含 sub 的唯一行，返回 index；找不到抛错
function findLine(ctx, sub, hint) {
  const hits = []
  ctx.lines.forEach((l, i) => { if (l.includes(sub)) hits.push(i) })
  if (hits.length !== 1) throw new Error(`${ctx.p}: expect 1 hit for "${sub}", got ${hits.length} (${hint})`)
  return hits[0]
}
function insertAfter(ctx, idx, text) {
  ctx.lines.splice(idx + 1, 0, ...text.split('\n'))
  edits++
}
function replaceLine(ctx, idx, newline) {
  ctx.lines[idx] = newline
  edits++
}

// ============ MCPServer.ets ============
{
  const c = load('entry/src/main/ets/service/MCPServer.ets')
  // B: import cryptoFramework + util —— 已由 edit_file 加了 cryptoFramework 行，补 util
  if (!c.lines.some(l => l.includes("import { util } from '@kit.ArkTS'"))) {
    const i = findLine(c, "import { cryptoFramework } from '@kit.CryptoArchitectureKit'", 'mcpserver-crypto-import')
    insertAfter(c, i, "import { util } from '@kit.ArkTS'")
  }
  // B: generateRequestId / generateAuthToken → CSPRNG
  const iReq = findLine(c, 'return `req_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`', 'reqid')
  replaceLine(c, iReq, '    // P42: CSPRNG 随机段（KAI-044）替代 Math.random\n    return `req_${Date.now()}_${this.secureRandomChars(8)}`')
  const iTok = findLine(c, 'const chars = \'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\'', 'token-chars')
  // 向上找 generateAuthToken 的函数体：从 iTok 前一行(for 前的 let token) 到循环结束
  const iLet = iTok + 1 // let token = ''
  const iFor = iTok + 2 // for (let i = 0; ...
  if (!c.lines[iLet].includes('let token') || !c.lines[iFor].includes('for (let i')) throw new Error('token body mismatch')
  const iEnd = iFor + 1 // }
  // 用新实现整块替换 [iTok-? ... iEnd]：先找 generateAuthToken 行
  let iFn = iTok - 1
  while (!c.lines[iFn].includes('generateAuthToken()')) iFn--
  // 替换 iFn..iEnd（含）为新实现
  const impl = [
    '  generateAuthToken(): string {',
    '    // P42: CSPRNG 生成（KAI-044）——格式不变（AUTH_TOKEN_LENGTH 位字母数字）',
    '    return this.secureRandomChars(Constants.AUTH_TOKEN_LENGTH)',
    '  }',
    '',
    '  /** P42: cryptoFramework CSPRNG → base62 字符串；异常回退 util.generateRandomUUID 派生（同为系统安全随机源），绝不用 Math.random */',
    '  private secureRandomChars(len: number): string {',
    "    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'",
    '    try {',
    '      const rand = cryptoFramework.createRandom()',
    '      const bytes: Uint8Array = rand.generateRandomSync(len).data',
    "      let out = ''",
    '      for (let i = 0; i < len; i++) {',
    '        out += chars.charAt(bytes[i] % chars.length)',
    '      }',
    '      return out',
    '    } catch (e) {',
    "      console.error('[MCPServer] generateRandomSync failed, fallback to uuid-derived: ' + JSON.stringify(e))",
    '      let hex = \'\'',
    '      while (hex.length < len * 2) {',
    '        hex += util.generateRandomUUID(false).replace(/-/g, \'\')',
    '      }',
    "      let out = ''",
    '      for (let i = 0; i < len; i++) {',
    '        out += chars.charAt(parseInt(hex.substring(i * 2, i * 2 + 2), 16) % chars.length)',
    '      }',
    '      return out',
    '    }',
    '  }'
  ]
  c.lines.splice(iFn, iEnd - iFn + 1, ...impl)
  edits++

  // C: handleType 敏感 gate（detectType + requestConfirmation，与 navigate/click 同款）
  const iType = findLine(c, 'const result = await BCPEngine.type(selector, text)', 'type-body')
  const gate = [
    '    // P42 (KAI-074): type 工具走敏感操作 gate——输入文本/目标 selector 过 SensitiveOperationDetector',
    '    const sensitiveType = SensitiveOperationDetector.detectType(agentId, selector, text)',
    '    if (sensitiveType) {',
    '      const confirmed = await SensitiveOperationDetector.requestConfirmation(',
    "        agentId, sensitiveType, text, selector)",
    '      if (!confirmed) {',
    "        return this.errorResponse(ErrorCodes.AGT_003, 'Operation rejected by user')",
    '      }',
    '    }',
    ''
  ]
  insertAfter(c, iType - 1, gate.join('\n'))
  save(c)
  console.log('MCPServer.ets patched')
}

// ============ HttpMcpTransport.ets (A) ============
{
  const c = load('entry/src/main/ets/service/HttpMcpTransport.ets')
  const i = findLine(c, "await server.listen({ address: '0.0.0.0', port: port })", 'http-listen')
  replaceLine(c, i, '      // P42 (KAI-047): loopback only——宿主经 hdc fport 隧道（guest 内 hdcd 走 loopback）仍通，设备 IP 直连被拒\n      await server.listen({ address: \'127.0.0.1\', port: port })')
  const iLog = findLine(c, 'listening on 0.0.0.0:', 'http-log')
  replaceLine(c, iLog, c.lines[iLog].replace('0.0.0.0', '127.0.0.1'))
  save(c)
  console.log('HttpMcpTransport.ets patched')
}

// ============ WsMcpTransport.ets (A) ============
{
  const c = load('entry/src/main/ets/service/WsMcpTransport.ets')
  const i = findLine(c, "await server.listen({ address: '0.0.0.0', port: port })", 'ws-listen')
  replaceLine(c, i, '      // P42 (KAI-047): loopback only（与 HTTP 9222 同款决策）\n      await server.listen({ address: \'127.0.0.1\', port: port })')
  const iLog = findLine(c, 'listening on 8765', 'ws-log')
  replaceLine(c, iLog, c.lines[iLog].replace('listening on', 'listening on 127.0.0.1:'))
  save(c)
  console.log('WsMcpTransport.ets patched')
}

// ============ SensitiveOperationDetector.ets (C: detectType) ============
{
  const c = load('entry/src/main/ets/service/SensitiveOperationDetector.ets')
  const i = findLine(c, 'detectNavigation(agentId: string, url: string)', 'detect-nav')
  const fn = [
    '  /** P42 (KAI-074): type 工具输入检测——selector 与 text 合并走敏感词表（password/payment/删除/设置类） */',
    '  detectType(agentId: string, selector: string, text: string): SensitiveOperationType | null {',
    '    // selector 权重同 click；text 单独再扫一遍（输入内容含敏感词也算）',
    '    const clickLike = this.detectClick(agentId, selector, text)',
    '    if (clickLike) {',
    '      return clickLike',
    '    }',
    '    return this.detectNavigation(agentId, text)',
    '  }',
    ''
  ]
  insertAfter(c, i - 1, fn.join('\n'))
  save(c)
  console.log('SensitiveOperationDetector.ets patched')
}

// ============ McpJsonRpcCore.ets (D) ============
{
  const c = load('entry/src/main/ets/service/McpJsonRpcCore.ets')
  // import redact
  if (!c.lines.some(l => l.includes("import { redactSensitive } from '../common/Redact'"))) {
    const i = findLine(c, "import { util } from '@kit.ArkTS'", 'rpc-import')
    insertAfter(c, i, "import { redactSensitive } from '../common/Redact'")
  }
  // tools/call 成功路径
  const i = findLine(c, "item.text = response.data === null ? 'ok' : JSON.stringify(response.data)", 'rpc-itemtext')
  replaceLine(c, i, '        // P42 (KAI-075): 工具输出统一脱敏\n        item.text = redactSensitive(response.data === null ? \'ok\' : JSON.stringify(response.data))')
  // 失败路径 rpcError message 也脱敏
  const iErr = findLine(c, 'return this.outcome(rpcId, this.rpcError(-32000, response.error || \'tool call failed\'))', 'rpc-err')
  replaceLine(c, iErr, "      return this.outcome(rpcId, this.rpcError(-32000, redactSensitive(response.error || 'tool call failed')))")
  save(c)
  console.log('McpJsonRpcCore.ets patched')
}

// ============ AuditLogger.ets (D) ============
{
  const c = load('entry/src/main/ets/storage/AuditLogger.ets')
  if (!c.lines.some(l => l.includes("import { redactSensitive } from '../common/Redact'"))) {
    const i = findLine(c, "import { Constants } from '../common/Constants'", 'audit-import')
    insertAfter(c, i, "import { redactSensitive } from '../common/Redact'")
  }
  const i = findLine(c, 'const lines = this.logQueue.map(entry => entry.toLogString()).join(\'\\n\')', 'audit-lines')
  replaceLine(c, i, "    // P42 (KAI-075): 审计写入统一脱敏（逐行）\n    const lines = this.logQueue.map(entry => redactSensitive(entry.toLogString())).join('\\n')")
  save(c)
  console.log('AuditLogger.ets patched')
}

// ============ SessionManager.ets (E) ============
{
  const c = load('entry/src/main/ets/service/SessionManager.ets')
  const i = findLine(c, 'const sortedFiles = files.sort()', 'e-sort')
  const impl = [
    '    // P42 (KAI-061): 清理按真实时间——读每个会话文件的 startTime 升序淘汰（最旧先删），',
    '    // 不再用文件名字符串序；parse 失败的文件视为最旧（优先清理）。删后同步索引与内存镜像。',
    '    const timed: { file: string, startTime: number }[] = []',
    '    for (const f of files) {',
    '      let st = -1',
    '      try {',
    "        const content = await StorageManager.load('sessions/' + f)",
    '        if (content) {',
    '          const json = JSON.parse(content) as Record<string, Object>',
    "          const v = json['startTime']",
    '          if (typeof v === \'number\') {',
    '            st = v',
    '          }',
    '        }',
    '      } catch (e) {',
    '        // parse 失败保持 st=-1（排最旧）',
    '      }',
    '      timed.push({ file: f, startTime: st })',
    '    }',
    '    timed.sort((a, b): number => a.startTime - b.startTime)',
    '    const toDelete = Math.ceil(timed.length * 0.2)',
    '    for (let i2 = 0; i2 < toDelete; i2++) {',
    "      await StorageManager.delete(`sessions/${timed[i2].file}`)",
    '      const sid = timed[i2].file.replace(/\\.json$/, \'\')',
    '      await this.removeFromIndex(sid)',
    '      this.persistedSessions = this.persistedSessions.filter((s: SessionRecord): boolean => s.sessionId !== sid)',
    "      console.info('[SessionManager] cleanup removed oldest session: ' + sid + ' startTime=' + timed[i2].startTime)",
    '    }'
  ]
  // 替换原块：从 sortedFiles 行到 for 循环结束（含）
  let iEnd = i
  while (!c.lines[iEnd].includes('await StorageManager.delete(`sessions/${sortedFiles[i]}`)')) iEnd++
  c.lines.splice(i, iEnd - i + 1, ...impl)
  edits++
  save(c)
  console.log('SessionManager.ets patched')
}

// ============ BrowserShell.ets (G) ============
{
  const c = load('entry/src/main/ets/pages/BrowserShell.ets')
  const i = findLine(c, 'return /^(https?:\\/\\/)?([\\w-]+\\.)+[\\w-]+(:\\d{1,5})?(\\/[\\w-./?%&=]*)?$/.test(input)', 'g-isurl')
  replaceLine(c, i, '    // P42 (KAI-073): 白名单追回 localhost/127.0.0.1（无点主机 + 端口也按 URL 处理，其余行为不变）\n    if (/^(https?:\\/\\/)?(localhost|127\\.0\\.0\\.1)(:\\d{1,5})?(\\/[\\w-./?%&=]*)?$/.test(input)) {\n      return true\n    }\n    return /^(https?:\\/\\/)?([\\w-]+\\.)+[\\w-]+(:\\d{1,5})?(\\/[\\w-./?%&=]*)?$/.test(input)')
  save(c)
  console.log('BrowserShell.ets patched')
}

// ============ EntryAbility.ets (注释同步 A) ============
{
  const c = load('entry/src/main/ets/entryability/EntryAbility.ets')
  const i = findLine(c, 'HTTP transport 监听 0.0.0.0:{mcpPort}', 'ea-comment')
  replaceLine(c, i, c.lines[i].replace('0.0.0.0', '127.0.0.1'))
  save(c)
  console.log('EntryAbility.ets patched')
}

console.log('TOTAL edits:', edits)
