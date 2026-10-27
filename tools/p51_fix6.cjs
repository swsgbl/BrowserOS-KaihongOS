// P51 fix: MCPServer route waits for target tab's webview registration
const fs = require('fs')
const FILE = 'entry/src/main/ets/service/MCPServer.ets'
let s = fs.readFileSync(FILE, 'utf8')
const D = s.includes('\r\n') ? '\r\n' : '\n'
function rep(o, n, tag) {
  const oo = o.split('\n').join(D), nn = n.split('\n').join(D)
  if (s.includes(nn)) { console.log('skip: ' + tag); return }
  if (!s.includes(oo)) { console.error('MISS: ' + tag); process.exit(1) }
  s = s.replace(oo, nn)
  console.log('ok: ' + tag)
}

rep(`      if (session.ownedTabIds.indexOf(routeTab) >= 0) {
        TabManager.switchTab(routeTab)
        console.info('[P51] route sid=' + sessionId.substring(0, 8) + ' -> tab ' + routeTab + ' ' + toolName)
      } else {`,
    `      if (session.ownedTabIds.indexOf(routeTab) >= 0) {
        TabManager.switchTab(routeTab)
        // P51: MCP-created tab 的 Web 组件由 UI 异步渲染（onTabStatusChange -> ForEach -> onAttached
        // -> registerController -> BCPEngine.bindWebView）。路由后若尚未注册，轮询等待（最长 ~3s）。
        const t0 = Date.now()
        while (!TabManager.getWebView(routeTab) && Date.now() - t0 < 3000) {
          await new Promise<void>((res) => setTimeout(res, 100))
        }
        const wv = TabManager.getWebView(routeTab)
        if (wv) {
          BCPEngine.bindWebView(wv.controller, routeTab)
        } else {
          console.warn('[P51] route: webview not ready for tab ' + routeTab + ' after 3s — proceed on current binding')
        }
        console.info('[P51] route sid=' + sessionId.substring(0, 8) + ' -> tab ' + routeTab + ' ' + toolName + ' wvReady=' + (wv !== null))
      } else {`, 'route-wait')

fs.writeFileSync(FILE, s, 'utf8')
console.log('done')
