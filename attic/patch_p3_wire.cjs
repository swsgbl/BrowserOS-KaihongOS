// P3 patch 2: EntryAbility MCP start/stop + B-fixes (isUrl port, LLMClient catch, TabManager agent tab title, BrowserShell ForEach key)
const fs = require('fs')

function load(p) { return fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n') }
function save(p, s) { fs.writeFileSync(p, s.replace(/\n/g, '\r\n')) }

// ---------- 1) EntryAbility: start MCPServer after config load; stop in onDestroy ----------
{
  const p = 'entry/src/main/ets/entryability/EntryAbility.ets'
  let s = load(p)
  const orig = s
  const anchor = `    ConfigManager.load().then((config) => {
      console.info('EntryAbility ConfigManager loaded, mcpPort=' + config.mcpPort)
    }).catch((e: BusinessError) => {
      console.error('EntryAbility ConfigManager load error: ' + e.message)
    })`
  const repl = `    ConfigManager.load().then((config) => {
      console.info('EntryAbility ConfigManager loaded, mcpPort=' + config.mcpPort)
      // P3: 启动 MCP 网络层（HTTP transport 监听 0.0.0.0:{mcpPort}，token 每次启动新生成）
      const token = MCPServer.generateAuthToken()
      MCPServer.start(config.mcpPort, token).then((ok) => {
        if (ok) {
          console.info('EntryAbility MCPServer started on port ' + config.mcpPort)
        } else {
          console.error('EntryAbility MCPServer start FAILED on port ' + config.mcpPort)
        }
      }).catch((e: BusinessError) => {
        console.error('EntryAbility MCPServer start error: ' + e.code + '/' + e.message)
      })
    }).catch((e: BusinessError) => {
      console.error('EntryAbility ConfigManager load error: ' + e.message)
    })`
  if (!s.includes(anchor)) { console.error('FAIL: EntryAbility load anchor'); process.exit(1) }
  s = s.replace(anchor, repl)

  const anchorImp = `import { ConfigManager } from '../storage/ConfigManager'`
  const replImp = anchorImp + `
import { MCPServer } from '../service/MCPServer'`
  if (!s.includes(anchorImp)) { console.error('FAIL: EntryAbility import anchor'); process.exit(1) }
  s = s.replace(anchorImp, replImp)

  const anchorDestroy = `  onDestroy(): void {
    console.info('BrowserOS KaihongOS EntryAbility onDestroy')
  }`
  const replDestroy = `  onDestroy(): void {
    console.info('BrowserOS KaihongOS EntryAbility onDestroy')
    // P3: 停 MCP 网络层（释放端口与连接）
    MCPServer.stop().catch((e: BusinessError) => {
      console.error('EntryAbility MCPServer stop error: ' + e.code + '/' + e.message)
    })
  }`
  if (!s.includes(anchorDestroy)) { console.error('FAIL: EntryAbility onDestroy anchor'); process.exit(1) }
  s = s.replace(anchorDestroy, replDestroy)

  save(p, s)
  console.log('OK EntryAbility delta=' + (s.length - orig.length))
}

// ---------- 2) BrowserShell.isUrl: support port ----------
{
  const p = 'entry/src/main/ets/pages/BrowserShell.ets'
  let s = load(p)
  const orig = s
  const anchor = `  private isUrl(input: string): boolean {
    return /^(https?:\\/\\/)?([\\w-]+\\.)+[\\w-]+(\\/[\\w-./?%&=]*)?$/.test(input)
  }`
  const repl = `  private isUrl(input: string): boolean {
    // P3 修复：host 支持端口号（如 http://host:11435/path）
    return /^(https?:\\/\\/)?([\\w-]+\\.)+[\\w-]+(:\\d{1,5})?(\\/[\\w-./?%&=]*)?$/.test(input)
  }`
  if (!s.includes(anchor)) { console.error('FAIL: isUrl anchor'); process.exit(1) }
  s = s.replace(anchor, repl)

  // ForEach keyGenerator：agent tab 后加进来时确保按 tabId 稳定 diff 刷新
  const feAnchor = `      ForEach(this.tabs, (tab: TabInfo) => {`
  const feRepl = `      ForEach(this.tabs, (tab: TabInfo) => {`
  if (!s.includes(feAnchor)) { console.error('FAIL: ForEach anchor'); process.exit(1) }
  // 找到 ForEach 结束的 `})` 前插入 keyGenerator —— ForEach 三参数形式：需要定位 ForEach 块尾部。
  // 简单可靠法：ForEach(this.tabs, cb) 改成 ForEach(this.tabs, cb, (tab: TabInfo) => tab.tabId)
  // 定位：从 feAnchor 开始匹配第一个 `      })\n\n      Button({ type: ButtonType.Normal }) {` 的位置
  const tailMarker = `\n      })\n\n      Button({ type: ButtonType.Normal }) {\n        Text('+')`
  const idx = s.indexOf(feAnchor)
  const tailIdx = s.indexOf(tailMarker, idx)
  if (tailIdx < 0) { console.error('FAIL: ForEach tail marker'); process.exit(1) }
  const newTail = `\n      }, (tab: TabInfo) => tab.tabId)\n\n      Button({ type: ButtonType.Normal }) {\n        Text('+')`
  s = s.substring(0, tailIdx) + newTail + s.substring(tailIdx + tailMarker.length)

  // agent tab 创建后无标题：显示 agent 标记（TabManager 侧也会设 title，这里兜底渲染）
  const titleAnchor = `          Text(tab.title || '新标签页')`
  const titleRepl = `          Text(tab.title || (tab.agentId ? '代理 ' + tab.agentId.substring(0, 12) : '新标签页'))`
  if (!s.includes(titleAnchor)) { console.error('FAIL: tab title anchor'); process.exit(1) }
  s = s.replace(titleAnchor, titleRepl)

  save(p, s)
  console.log('OK BrowserShell delta=' + (s.length - orig.length))
}

// ---------- 3) LLMClient catch: full error detail ----------
{
  const p = 'entry/src/main/ets/service/LLMClient.ets'
  let s = load(p)
  const orig = s
  const anchor = `    } catch (e) {
      ErrorHandler.handle(new AppError(ErrorCodes.SYS_001, \`LLM request failed: \${e}\`))
      return null
    } finally {
      httpRequest.destroy()
    }`
  const repl = `    } catch (e) {
      // P3 修复：完整异常详情（P2 终验发现 \`\${e}\` 在 hilog 不可见——BusinessError 模板串接产 [object Object] 且可能被截断）
      const detail = e instanceof BusinessError ? e.code + '/' + e.message : JSON.stringify(e)
      console.error(\`[\${TAG}] request exception: code=\${e instanceof BusinessError ? e.code : ''} message=\${detail}\`)
      ErrorHandler.handle(new AppError(ErrorCodes.SYS_001, \`LLM request failed: \${detail}\`))
      return null
    } finally {
      httpRequest.destroy()
    }`
  if (!s.includes(anchor)) { console.error('FAIL: LLMClient catch anchor'); process.exit(1) }
  s = s.replace(anchor, repl)

  // import BusinessError
  if (!s.includes('@kit.BasicServicesKit')) {
    const impAnchor = `import { http } from '@kit.NetworkKit'`
    s = s.replace(impAnchor, impAnchor + `
import { BusinessError } from '@kit.BasicServicesKit'`)
  }

  save(p, s)
  console.log('OK LLMClient delta=' + (s.length - orig.length))
}

// ---------- 4) TabManager: agent tab gets a visible title ----------
{
  const p = 'entry/src/main/ets/service/TabManager.ets'
  let s = load(p)
  const orig = s
  const anchor = `  createAgentTab(agentId: string): TabInfo {
    const tabId = this.generateTabId()
    const tab = new TabInfo(tabId, agentId, false)
    this.tabs.set(tabId, tab)
    EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, tab.toJSON())
    return tab
  }`
  const repl = `  createAgentTab(agentId: string): TabInfo {
    const tabId = this.generateTabId()
    const tab = new TabInfo(tabId, agentId, false)
    tab.title = 'Agent ' + agentId.substring(agentId.length - 6)
    this.tabs.set(tabId, tab)
    // P3 修复：agent tab 立即可见于标签栏（BrowserShell 监听 TAB_STATUS_CHANGE 刷新）
    EventBus.emit(EventBusEvents.TAB_STATUS_CHANGE, tab.toJSON())
    return tab
  }`
  if (!s.includes(anchor)) { console.error('FAIL: createAgentTab anchor'); process.exit(1) }
  s = s.replace(anchor, repl)
  save(p, s)
  console.log('OK TabManager delta=' + (s.length - orig.length))
}

console.log('ALL PATCHES DONE')
