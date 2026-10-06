// P3 fix: BusinessError is an interface (type-only) — `instanceof` rejected by ArkTS strict mode.
// Replace with property probe: (e as BusinessError).code !== undefined
const fs = require('fs')

function load(p) { return fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n') }
function save(p, s) { fs.writeFileSync(p, s.replace(/\n/g, '\r\n')) }

// HttpMcpTransport: 3 occurrences
{
  const p = 'entry/src/main/ets/service/HttpMcpTransport.ets'
  let s = load(p)
  const n = (s.match(/e instanceof BusinessError/g) || []).length
  s = s.replace(/const detail = e instanceof BusinessError \? `\$\{e\.code\}\/\$\{e\.message\}` : JSON\.stringify\(e\)/g,
    `const detail = (e as BusinessError).code !== undefined ? \`\${(e as BusinessError).code}/\${(e as BusinessError).message}\` : JSON.stringify(e)`)
  s = s.replace(/server\.on\('error', \(err: BusinessError\) => \{\r?\n      console\.error\(\`\[\$\{TAG\}\] server error: \$\{err\.code\}\/\$\{err\.message\}\`\)/,
    `server.on('error', (err: BusinessError) => {
      console.error(\`[\${TAG}] server error: \${err.code}/\${err.message}\`)`)
  save(p, s)
  const left = (s.match(/instanceof BusinessError/g) || []).length
  console.log('HttpMcpTransport: replaced, remaining instanceof=' + left + ' (was ' + n + ')')
}

// LLMClient: 2 occurrences
{
  const p = 'entry/src/main/ets/service/LLMClient.ets'
  let s = load(p)
  const anchor = `      // P3 修复：完整异常详情（P2 终验发现 \`\${e}\` 在 hilog 不可见——BusinessError 模板串接产 [object Object] 且可能被截断）
      const detail = e instanceof BusinessError ? e.code + '/' + e.message : JSON.stringify(e)
      console.error(\`[\${TAG}] request exception: code=\${e instanceof BusinessError ? e.code : ''} message=\${detail}\`)
      ErrorHandler.handle(new AppError(ErrorCodes.SYS_001, \`LLM request failed: \${detail}\`))
      return null`
  const repl = `      // P3 修复：完整异常详情（P2 终验发现 \`\${e}\` 在 hilog 不可见——BusinessError 模板串接产 [object Object] 且可能被截断）
      // BusinessError 是 interface 不能 instanceof：属性探测 code 字段
      const be = e as BusinessError
      const detail = be.code !== undefined ? be.code + '/' + be.message : JSON.stringify(e)
      console.error(\`[\${TAG}] request exception: code=\${be.code !== undefined ? be.code : 'N/A'} message=\${detail}\`)
      ErrorHandler.handle(new AppError(ErrorCodes.SYS_001, \`LLM request failed: \${detail}\`))
      return null`
  if (!s.includes(anchor)) { console.error('FAIL: LLMClient anchor'); process.exit(1) }
  s = s.replace(anchor, repl)
  save(p, s)
  console.log('LLMClient: patched')
}
console.log('DONE')
