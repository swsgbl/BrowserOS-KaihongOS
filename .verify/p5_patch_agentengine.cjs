const fs = require('fs');
const path = 'entry/src/main/ets/service/AgentEngine.ets';
let src = fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');

// ---- Patch: AgentEngine webview wait loop (P5-A2) ----
const OLD = `    // 绑定该 agent 的 tab 的 WebViewAdapter
    const instance = TabManager.getWebView(config.tabId)
    if (instance !== null && instance !== undefined && instance.controller) {
      BCPEngine.bindWebView(instance.controller, config.tabId)
      console.info('[AgentEngine] BCPEngine bound to tab ' + config.tabId)
    } else {
      console.warn('[AgentEngine] WebView not registered for tab ' + config.tabId + ' (agent tools will fail until tab opened)')
    }`;

const NEW = `    // P5: 等待该 agent 的 tab 的 Web 组件挂载（BrowserShell 多 Web 常驻架构下
    // 创建 tab 即挂载；若 BrowserShell 尚未渲染（覆盖态），轮询等待用户回到前台）
    let bound = false
    for (let wait = 0; wait < 20; wait++) {
      const instance = TabManager.getWebView(config.tabId)
      if (instance !== null && instance !== undefined && instance.controller) {
        BCPEngine.bindWebView(instance.controller, config.tabId)
        bound = true
        console.info('[AgentEngine] BCPEngine bound to tab ' + config.tabId + ' after ' + wait + ' polls')
        break
      }
      if (wait === 0) {
        console.info('[AgentEngine] waiting for webview on tab ' + config.tabId + ' (agent tab not rendered yet)')
      }
      await new Promise<void>((resolve) => { setTimeout(() => { resolve() }, 500) })
    }
    if (!bound) {
      console.warn('[AgentEngine] WebView not registered for tab ' + config.tabId + ' after 10s, agent tools will fail')
    }`;

if (!src.includes(OLD)) { throw new Error('anchor 1 not found'); }
if (src.split(OLD).length > 2) { throw new Error('anchor 1 not unique'); }
src = src.replace(OLD, NEW);

fs.writeFileSync(path, src.replace(/\n/g, '\r\n'), 'utf8');
console.log('AgentEngine patched OK');
