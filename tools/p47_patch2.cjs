/* P47 Phase2 patch: incognito tabs + zoom controls + network logging
   All patches EOL-normalized (read -> \n -> patch -> restore EOL). */
const fs = require('fs');
const PROJ = 'D:/BrowserOS - KaihongOS';
const ETS = PROJ + '/entry/src/main/ets';

function loadFile(p) {
  const raw = fs.readFileSync(p, 'utf8');
  const eol = (raw.match(/\r\n/g) || []).length >= (raw.match(/\n/g) || []).length / 2 ? '\r\n' : '\n';
  return { text: raw.replace(/\r\n/g, '\n'), eol };
}
function saveFile(p, text, eol) {
  fs.writeFileSync(p, eol === '\r\n' ? text.replace(/\n/g, '\r\n') : text, 'utf8');
}
function patch(src, oldStr, newStr, tag) {
  const i = src.indexOf(oldStr);
  if (i < 0) throw new Error('PATCH MISS: ' + tag);
  if (src.indexOf(oldStr, i + 1) >= 0) throw new Error('PATCH DUP: ' + tag);
  return src.slice(0, i) + newStr + src.slice(i + oldStr.length);
}

/* ---------- 1. BrowserShell.ets ---------- */
const shF = loadFile(ETS + '/pages/BrowserShell.ets');
let sh = shF.text;

// 1a states for incognito + zoom
sh = patch(sh, "  private p47WatchedTabs: Set<string> = new Set()",
  "  private p47WatchedTabs: Set<string> = new Set()\n" +
  "  // P47-C: \u65e0\u75d5\u6807\u7b7e\u96c6\u5408 / P47-D: \u7f29\u653e\n" +
  "  private p47IncognitoTabs: Set<string> = new Set()\n" +
  "  @State p47ZoomToast: string = ''",
  'states2');

// 1b Web component: incognitoMode + onInterceptRequest + zoom passthrough
sh = patch(sh, "          .onConsole((event) => {",
  "          .incognitoMode(this.p47IncognitoTabs.has(tab.tabId))\n" +
  "          .onInterceptRequest((event) => {\n" +
  "            // P47-A: Network \u65e5\u5fd7\u6536\u96c6\uff08\u4e0d\u62e6\u622a\uff0c\u8bb0\u5f55\u540e\u653e\u884c\uff09\n" +
  "            if (event && event.request) {\n" +
  "              try {\n" +
  "                const req = event.request\n" +
  "                let hdr = ''\n" +
  "                const hs = req.getRequestHeader()\n" +
  "                for (const h of hs) {\n" +
  "                  hdr += h.headerKey + '=' + h.headerValue + '; '\n" +
  "                }\n" +
  "                DevToolsCollector.addNetwork(tab.tabId, req.getUrl(), req.getMethod(), hdr)\n" +
  "              } catch (e) {\n" +
  "                // \u8bb0\u5f55\u5931\u8d25\u4e0d\u963b\u65ad\u52a0\u8f7d\n" +
  "              }\n" +
  "            }\n" +
  "            return null\n" +
  "          })\n" +
  "          .onConsole((event) => {",
  'webAttrs');

// 1c menu actions: incognito tab + zoom
sh = patch(sh, "      case 'passwords':",
  "      case 'new_incognito':\n" +
  "        // P47-C: \u65b0\u5efa\u65e0\u75d5\u6807\u7b7e\u9875\n" +
  "        this.p47CreateIncognitoTab()\n" +
  "        break\n" +
  "      case 'zoom_in':\n" +
  "        this.p47Zoom(0.25)\n" +
  "        break\n" +
  "      case 'zoom_out':\n" +
  "        this.p47Zoom(-0.25)\n" +
  "        break\n" +
  "      case 'zoom_reset':\n" +
  "        this.p47ZoomReset()\n" +
  "        break\n" +
  "      case 'passwords':",
  'menu2');

// 1d methods: incognito + zoom
sh = patch(sh, "  /** P47-B: \u57df\u540d\u63d0\u53d6 */",
  "  /** P47-C: \u65b0\u5efa\u65e0\u75d5\u6807\u7b7e\uff08\u6807\u8bb0\u96c6\u5408 + TabManager \u4e0d\u6301\u4e45\u5316\u5355 tab \u4f8b\u5916\uff09 */\n" +
  "  private p47CreateIncognitoTab(): void {\n" +
  "    const tab = TabManager.createTab(false)\n" +
  "    if (!tab) {\n" +
  "      return\n" +
  "    }\n" +
  "    this.p47IncognitoTabs.add(tab.tabId)\n" +
  "    this.tabs = TabManager.getTabs()\n" +
  "    this.activeTabId = tab.tabId\n" +
  "    this.showDashboard = false\n" +
  "    console.info('[P47] incognito tab created: ' + tab.tabId)\n" +
  "  }\n" +
  "\n" +
  "  /** P47-D: \u7f29\u653e\uff08\u5bf9\u6d3b\u52a8 tab \u7684 WebviewController \u8c03 zoom\uff09 */\n" +
  "  private p47Zoom(delta: number): void {\n" +
  "    const native = this.controllers.get(this.activeTabId)\n" +
  "    if (!native) {\n" +
  "      return\n" +
  "    }\n" +
  "    try {\n" +
  "      native.zoom(delta)\n" +
  +
  "      this.p47FlashToast((delta > 0 ? '\u653e\u5927' : '\u7f29\u5c0f') + ' \u00b7 ' + Math.round((this.p47CurZoom + delta) * 100) + '%')\n" +
  "    } catch (e) {\n" +
  "      console.warn('[P47] zoom fail: ' + e)\n" +
  "    }\n" +
  "  }\n" +
  "\n" +
  "  private p47ZoomReset(): void {\n" +
  "    const native = this.controllers.get(this.activeTabId)\n" +
  "    if (!native) {\n" +
  "      return\n" +
  "    }\n" +
  "    try {\n" +
  "      native.zoom(1)\n" +
  "      this.p47FlashToast('\u91cd\u7f6e\u7f29\u653e 100%')\n" +
  "    } catch (e) {\n" +
  "      console.warn('[P47] zoom reset fail: ' + e)\n" +
  "    }\n" +
  "  }\n" +
  "\n" +
  "  private p47CurZoom: number = 1\n" +
  "\n" +
  "  private p47FlashToast(msg: string): void {\n" +
  "    this.p47ZoomToast = msg\n" +
  "    setTimeout(() => {\n" +
  "      if (this.p47ZoomToast === msg) {\n" +
  "        this.p47ZoomToast = ''\n" +
  "      }\n" +
  "    }, 1500)\n" +
  "  }\n" +
  "\n" +
  "  /** P47-B: \u57df\u540d\u63d0\u53d6 */",
  'methods2');

saveFile(ETS + '/pages/BrowserShell.ets', sh, shF.eol);
console.log('BrowserShell.ets patched (phase2)');

/* ---------- 2. ChromeWidgets.ets menu ---------- */
const cwF = loadFile(ETS + '/components/ChromeWidgets.ets');
let cw = cwF.text;
// new_incognito in group1 after new_window
cw = patch(cw, "    { icon: $rawfile('ic_content_copy.svg'), label: '\u65b0\u7a97\u53e3', action: 'new_window' }\n  ]",
  "    { icon: $rawfile('ic_content_copy.svg'), label: '\u65b0\u7a97\u53e3', action: 'new_window' },\n" +
  "    { icon: $rawfile('ic_incognito.svg'), label: '\u65b0\u5efa\u65e0\u75d5\u6807\u7b7e\u9875', action: 'new_incognito' }\n  ]",
  'menu-incognito');
// zoom group before devtools
cw = patch(cw, "    { icon: $rawfile('ic_bug.svg'), label: '\u5f00\u53d1\u8005\u5de5\u5177', action: 'devtools' },",
  "    { icon: $rawfile('ic_zoom_search.svg'), label: '\u653e\u5927', action: 'zoom_in' },\n" +
  "    { icon: $rawfile('ic_zoom_out.svg'), label: '\u7f29\u5c0f', action: 'zoom_out' },\n" +
  "    { icon: $rawfile('ic_reload.svg'), label: '\u91cd\u7f6e\u7f29\u653e', action: 'zoom_reset' },\n" +
  "    { icon: $rawfile('ic_bug.svg'), label: '\u5f00\u53d1\u8005\u5de5\u5177', action: 'devtools' },",
  'menu-zoom');
saveFile(ETS + '/components/ChromeWidgets.ets', cw, cwF.eol);
console.log('ChromeWidgets.ets patched (phase2)');
console.log('PHASE2 PATCHES OK');
