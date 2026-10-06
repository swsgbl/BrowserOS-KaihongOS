const fs = require('fs');
const p = 'D:\\BrowserOS - KaihongOS\\entry\\src\\main\\ets\\pages\\BrowserShell.ets';
let c = fs.readFileSync(p, 'utf8');

function rep(oldStr, newStr, tag) {
  if (!c.includes(oldStr)) { console.log('MISS: ' + tag); process.exitCode = 1; return; }
  c = c.split(oldStr).join(newStr);
  console.log('OK: ' + tag);
}

rep("interface PageLoadErrorData {\n  tabId: string\n  error: string\n}",
    "interface PageLoadErrorData {\n  tabId: string\n  error: string\n}\n\ninterface PageLoadCompleteData {\n  tabId: string\n  url: string\n}",
    'PageLoadCompleteData interface');

rep("        .onControllerAttached(() => {\n          console.info('BrowserShell onControllerAttached tabId=' + this.activeTabId)\n          this.attachedTabs.add(this.activeTabId)\n          this.registerController(this.activeTabId)\n        })",
    "        .onControllerAttached(() => {\n          console.info('BrowserShell onControllerAttached tabId=' + this.activeTabId)\n          this.attachedTabs.add(this.activeTabId)\n          this.registerController(this.activeTabId)\n          if (this.pendingUrl) {\n            const url = this.pendingUrl\n            this.pendingUrl = ''\n            try {\n              this.getActiveController()?.loadUrl(url)\n              console.info('BrowserShell pendingUrl loaded after attach: ' + url)\n            } catch (e) {\n              console.error('BrowserShell pendingUrl load error: ' + e)\n            }\n          }\n        })",
    'onControllerAttached pendingUrl');

rep("    } else {\n      // controller 尚未 attach（首次从 Dashboard 进入）：记目标 URL，onControllerAttached 后加载\n      console.info('BrowserShell controller not ready yet, url pending: ' + url)\n    }",
    "    } else {\n      // controller 尚未 attach（首次从 Dashboard 进入）：记目标 URL，onControllerAttached 后加载\n      this.pendingUrl = url\n      console.info('BrowserShell controller not ready yet, url pending: ' + url)\n    }",
    'navigate pendingUrl');

rep("          console.error('BrowserShell onErrorReceive url=' + (event.request ? event.request.getUrl() : '') +\n            ' error=' + (event.error ? event.error.getErrorInfo() : ''))",
    "          console.error('BrowserShell onErrorReceive url=' + (event.request ? event.request.getRequestUrl() : '') +\n            ' error=' + (event.error ? event.error.getErrorInfo() : ''))",
    'onErrorReceive getRequestUrl');

fs.writeFileSync(p, c);
console.log('done');
