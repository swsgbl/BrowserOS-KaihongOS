// P65 E2E probe: initialize -> tools/list (assert 19 + llm_config/agent_task) -> llm_config set/get/test -> agent_task create/status/result
const BASE = 'http://127.0.0.1:19322/mcp?token=' + (process.env.P65_TOKEN || 'ToZoGzCcGuo8RIrPfCKxKENhSmzrlzQi')
const KEY = process.env.P65_KEY || 'sk-ZzeLuzxw4AgkL90FF7QUSgYoL8DNG1Z2Kt3kHpiKJjOgTHdt'
let sid = ''
let n = 0

async function rpc(method, params) {
  const headers = { 'Content-Type': 'application/json' }
  if (sid) headers['Mcp-Session-Id'] = sid
  const res = await fetch(BASE, {
    method: 'POST', headers,
    body: JSON.stringify({ jsonrpc: '2.0', id: ++n, method, params: params || {} })
  })
  const newsid = res.headers.get('mcp-session-id')
  if (newsid) sid = newsid
  const text = await res.text()
  if (!text) return { status: res.status, body: null }
  return { status: res.status, body: JSON.parse(text) }
}

function toolText(r) {
  const c = r.body && r.body.result && r.body.result.content
  if (!c || !c[0]) return ''
  try { return JSON.parse(c[0].text) } catch (e) { return c[0].text }
}

async function call(name, args) {
  return rpc('tools/call', { name, arguments: args })
}

function log(tag, obj) {
  console.log('== ' + tag + ' ==')
  console.log(typeof obj === 'string' ? obj : JSON.stringify(obj, null, 1))
}

(async () => {
  let r = await rpc('initialize', { protocolVersion: '2024-11-05', clientInfo: { name: 'p65-e2e', version: '1.0' } })
  log('initialize status=' + r.status, r.body && r.body.result && r.body.result.serverInfo)
  if (!r.body || !r.body.result) process.exit(1)

  r = await rpc('tools/list', {})
  const names = (r.body.result.tools || []).map(t => t.name)
  log('tools/list count=' + names.length, names)
  const hasCfg = names.includes('llm_config'), hasTask = names.includes('agent_task')
  console.log('ASSERT 19 tools:', names.length === 19, '| llm_config:', hasCfg, '| agent_task:', hasTask)
  if (names.length !== 19 || !hasCfg || !hasTask) process.exit(2)

  r = await call('llm_config', { action: 'set', apiKey: KEY })
  log('llm_config set', toolText(r))

  r = await call('llm_config', { action: 'get' })
  log('llm_config get', toolText(r))

  r = await call('llm_config', { action: 'test' })
  log('llm_config test', toolText(r))

  r = await call('agent_task', { action: 'create', prompt: '打开 https://example.com 并用一句话总结页面', targetUrl: 'https://example.com' })
  const created = toolText(r)
  log('agent_task create', created)
  const agentId = created && created.agentId
  if (!agentId) process.exit(3)

  for (let i = 0; i < 20; i++) {
    await new Promise(res => setTimeout(res, 6000))
    r = await call('agent_task', { action: 'status', agentId })
    const st = toolText(r)
    log('agent_task status #' + (i + 1), st)
    if (st && (st.status === 'completed' || st.status === 'COMPLETED' || st.status === 'failed' || st.status === 'error')) break
  }

  r = await call('agent_task', { action: 'result', agentId })
  log('agent_task result', toolText(r))
  console.log('P65 E2E DONE')
})().catch(e => { console.error('FATAL', e); process.exit(9) })
