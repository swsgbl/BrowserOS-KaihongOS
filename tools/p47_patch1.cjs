/* P47 Phase1 patch v2: EOL-normalizing patcher.
   Strategy: read file -> detect dominant EOL -> normalize to \n -> patch (all anchors in \n) -> restore EOL on write. */
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

sh = patch(sh, "import { ScheduleManager, ScheduleTask } from '../service/ScheduleManager'",
  "import { ScheduleManager, ScheduleTask } from '../service/ScheduleManager'\nimport { CredentialStore } from '../service/CredentialStore'\nimport { DevToolsCollector } from '../service/DevToolsCollector'",
  'imports');

sh = patch(sh, "  @State ctxLinkUrl: string = ''",
  "  @State ctxLinkUrl: string = ''\n" +
  "  // P47-B: \u5bc6\u7801\u586b\u5145\u63d0\u793a\u6761 / \u4fdd\u5b58\u5bc6\u7801\u5f39\u5c42\n" +
  "  @State p47ShowFillBar: boolean = false\n" +
  "  @State p47FillDomain: string = ''\n" +
  "  @State p47FillUser: string = ''\n" +
  "  @State p47FillPass: string = ''\n" +
  "  @State p47SaveOpen: boolean = false\n" +
  "  @State p47SaveDomain: string = ''\n" +
  "  @State p47SaveUser: string = ''\n" +
  "  @State p47SavePass: string = ''\n" +
  "  private p47WatchedTabs: Set<string> = new Set()",
  'states');

sh = patch(sh, "    this.initUltrafastPrefs()",
  "    this.initUltrafastPrefs()\n" +
  "    // P47-B: \u5bc6\u7801\u5e93\u521d\u59cb\u5316\n" +
  "    const p47ctx = this.getUIContext().getHostContext()\n" +
  "    if (p47ctx) {\n" +
  "      CredentialStore.init(p47ctx)\n" +
  "    }",
  'init');

sh = patch(sh, "          .onContextMenuShow((event) => {",
  "          .onConsole((event) => {\n" +
  "            // P47-A: DevTools Console \u65e5\u5fd7\u6536\u96c6\n" +
  "            const msg = event.message\n" +
  "            DevToolsCollector.addConsole(tab.tabId, msg.getMessageLevel(), msg.getSourceId(), 0, msg.getMessage())\n" +
  "            return false\n" +
  "          })\n" +
  "          .onContextMenuShow((event) => {",
  'onConsole');

sh = patch(sh, "            const completeData: PageLoadCompleteData = { tabId: tabId, url: url }\n            EventBus.emit(EventBusEvents.PAGE_LOAD_COMPLETE, completeData)",
  "            const completeData: PageLoadCompleteData = { tabId: tabId, url: url }\n" +
  "            EventBus.emit(EventBusEvents.PAGE_LOAD_COMPLETE, completeData)\n" +
  "            // P47-B: \u5bc6\u7801\u68c0\u6d4b\uff08\u975e\u65e0\u75d5\u6807\u7b7e\uff09\n" +
  "            this.p47OnPageEnd(tabId, url, controller)",
  'pwDetect');

sh = patch(sh, "      // P33-D: \u66f4\u65b0\u65e5\u5fd7\u5f39\u5c42",
  "      // P47-B: \u5bc6\u7801\u586b\u5145\u63d0\u793a\u6761\uff08\u5e95\u90e8\u60ac\u6d6e\uff09\n" +
  "      if (this.p47ShowFillBar) {\n" +
  "        Row({ space: 8 }) {\n" +
  "          Image($rawfile('ic_key.svg'))\n" +
  "            .width(16).height(16)\n" +
  "            .fillColor('#F9AB00')\n" +
  "            .draggable(false)\n" +
  "          Text('\u5bc6\u7801\u7ba1\u7406\u5668\u53ef\u586b\u5145 ' + this.p47FillDomain + ' \u7684\u767b\u5f55\u4fe1\u606f')\n" +
  "            .fontSize(12)\n" +
  "            .fontColor(this.pal().text)\n" +
  "            .layoutWeight(1)\n" +
  "            .maxLines(1)\n" +
  "            .textOverflow({ overflow: TextOverflow.Ellipsis })\n" +
  "          Button('\u586b\u5145')\n" +
  "            .fontSize(12)\n" +
  "            .height(30)\n" +
  "            .backgroundColor('#1A73E8')\n" +
  "            .fontColor('#FFFFFF')\n" +
  "            .onClick(() => { this.p47DoFill() })\n" +
  "          Button({ type: ButtonType.Normal }) {\n" +
  "            Image($rawfile('ic_close.svg'))\n" +
  "              .width(14).height(14)\n" +
  "              .fillColor(this.pal().text2)\n" +
  "              .draggable(false)\n" +
  "          }\n" +
  "          .width(30).height(30)\n" +
  "          .backgroundColor(Color.Transparent)\n" +
  "          .onClick(() => { this.p47DismissFill() })\n" +
  "        }\n" +
  "        .width('94%')\n" +
  "        .height(44)\n" +
  "        .padding({ left: 14, right: 10 })\n" +
  "        .borderRadius(10)\n" +
  "        .backgroundColor(this.pal().surface)\n" +
  "        .border({ width: 1, color: this.pal().border })\n" +
  "        .shadow({ radius: 12, color: '#44000000', offsetY: -2 })\n" +
  "        .position({ x: '3%', y: '86%' })\n" +
  "      }\n" +
  "      // P47-B: \u4fdd\u5b58\u5bc6\u7801\u5f39\u5c42\n" +
  "      if (this.p47SaveOpen) {\n" +
  "        Column()\n" +
  "          .width('100%')\n" +
  "          .height('100%')\n" +
  "          .backgroundColor('#66000000')\n" +
  "          .onClick(() => { this.p47SaveOpen = false })\n" +
  "        Column() {\n" +
  "          Text('\u4fdd\u5b58\u5bc6\u7801\uff1f')\n" +
  "            .fontSize(15)\n" +
  "            .fontWeight(FontWeight.Bold)\n" +
  "            .fontColor(this.pal().text)\n" +
  "            .alignSelf(ItemAlign.Start)\n" +
  "          Text(this.p47SaveDomain + ' \u00b7 ' + this.p47SaveUser)\n" +
  "            .fontSize(12)\n" +
  "            .fontColor(this.pal().text2)\n" +
  "            .margin({ top: 6 })\n" +
  "            .alignSelf(ItemAlign.Start)\n" +
  "            .maxLines(1)\n" +
  "            .textOverflow({ overflow: TextOverflow.Ellipsis })\n" +
  "          Row() {\n" +
  "            Button('\u4e0d\u4fdd\u5b58')\n" +
  "              .fontSize(13)\n" +
  "              .height(36)\n" +
  "              .layoutWeight(1)\n" +
  "              .backgroundColor(this.pal().surfaceAlt)\n" +
  "              .fontColor(this.pal().text)\n" +
  "              .onClick(() => { this.p47SaveOpen = false })\n" +
  "            Button('\u4fdd\u5b58')\n" +
  "              .fontSize(13)\n" +
  "              .height(36)\n" +
  "              .layoutWeight(1)\n" +
  "              .backgroundColor('#1A73E8')\n" +
  "              .fontColor('#FFFFFF')\n" +
  "              .margin({ left: 10 })\n" +
  "              .onClick(() => { this.p47DoSave() })\n" +
  "          }\n" +
  "          .width('100%')\n" +
  "          .margin({ top: 14 })\n" +
  "        }\n" +
  "        .width('72%')\n" +
  "        .padding(18)\n" +
  "        .borderRadius(14)\n" +
  "        .backgroundColor(this.pal().surface)\n" +
  "        .alignItems(HorizontalAlign.Center)\n" +
  "      }\n" +
  "      // P33-D: \u66f4\u65b0\u65e5\u5fd7\u5f39\u5c42",
  'bars');

sh = patch(sh, "      case 'find':",
  "      case 'passwords':\n" +
  "        // P47-B: \u5bc6\u7801\u7ba1\u7406\u5668\n" +
  "        router.pushUrl({ url: 'pages/PasswordsPage' })\n" +
  "        break\n" +
  "      case 'devtools':\n" +
  "        // P47-A: \u5f00\u53d1\u8005\u5de5\u5177\n" +
  "        router.pushUrl({ url: 'pages/DevToolsPage' })\n" +
  "        break\n" +
  "      case 'find':",
  'menu');

sh = patch(sh, "  /** \u65b0\u5efa\u7a7a\u767d\u6807\u7b7e\u9875\uff08\u5207\u5230 dashboard \u6001\uff09 */",
  "  /** P47-B: \u57df\u540d\u63d0\u53d6 */\n" +
  "  private p47DomainOf(url: string): string {\n" +
  "    const m = url.match(/^https?:\\/\\/([^\\/?#]+)/)\n" +
  "    return m && m.length > 1 ? m[1] : ''\n" +
  "  }\n" +
  "\n" +
  "  /** P47-B: \u9875\u9762\u52a0\u8f7d\u5b8c\u6210\u540e\u5bc6\u7801\u68c0\u6d4b \u2014\u2014 \u6709\u5bc6\u7801\u6846+\u5df2\u5b58\u51ed\u636e\u2192\u586b\u5145\u6761\uff1b\u65e0\u51ed\u636e\u2192\u6ce8\u5165 submit \u76d1\u542c\u5f85\u4fdd\u5b58 */\n" +
  "  private p47OnPageEnd(tabId: string, url: string, controller: IWebviewController | null): void {\n" +
  "    if (!url.startsWith('http') || !controller) {\n" +
  "      return\n" +
  "    }\n" +
  "    const domain = this.p47DomainOf(url)\n" +
  "    if (domain.length === 0) {\n" +
  "      return\n" +
  "    }\n" +
  "    controller.runJavaScript(\"(function(){var p=document.querySelectorAll('input[type=password]');return String(p.length)})()\").then((r: string) => {\n" +
  "      const n = parseInt(r)\n" +
  "      console.info('[P47] pw inputs on ' + domain + ': ' + n)\n" +
  "      if (!(n > 0)) {\n" +
  "        return\n" +
  "      }\n" +
  "      const creds = CredentialStore.getByDomain(domain)\n" +
  "      if (creds.length > 0 && tabId === this.activeTabId) {\n" +
  "        this.p47FillDomain = domain\n" +
  "        this.p47FillUser = creds[0].username\n" +
  "        this.p47FillPass = creds[0].password\n" +
  "        this.p47ShowFillBar = true\n" +
  "        console.info('[P47] fill bar shown for ' + domain)\n" +
  "      } else {\n" +
  "        this.p47StartSaveWatch(tabId, domain, controller)\n" +
  "      }\n" +
  "    }).catch((e: Object) => {\n" +
  "      console.warn('[P47] pw detect fail: ' + e)\n" +
  "    })\n" +
  "  }\n" +
  "\n" +
  "  /** P47-B: \u6ce8\u5165 submit \u76d1\u542c + \u8f6e\u8be2\u6355\u83b7\u65b0\u51ed\u636e\u2192\u4fdd\u5b58\u5f39\u5c42 */\n" +
  "  private p47StartSaveWatch(tabId: string, domain: string, controller: IWebviewController): void {\n" +
  "    if (this.p47WatchedTabs.has(tabId)) {\n" +
  "      return\n" +
  "    }\n" +
  "    this.p47WatchedTabs.add(tabId)\n" +
  "    controller.runJavaScript(\"(function(){if(window.__bwWatch)return '1';window.__bwWatch=1;document.addEventListener('submit',function(e){try{var f=e.target;if(!f)return;var pw=f.querySelector('input[type=password]');if(!pw)return;var un=f.querySelector('input[type=email]')||f.querySelector('input[type=text]')||f.querySelector('input:not([type])');window.__bw_cred={u:un?un.value:'',p:pw.value}}catch(_){}},true);return '0'})()\").catch(() => {})\n" +
  "    let tries = 0\n" +
  "    const timer = setInterval(() => {\n" +
  "      tries++\n" +
  "      controller.runJavaScript(\"(function(){return window.__bw_cred?JSON.stringify(window.__bw_cred):''})()\").then((r: string) => {\n" +
  "        const s = r.replace(/^\"|\"$/g, '')\n" +
  "        if (s.length > 0 && s !== 'undefined') {\n" +
  "          clearInterval(timer)\n" +
  "          try {\n" +
  "            const cred = JSON.parse(s) as Record<string, string>\n" +
  "            const u = cred['u'] ?? ''\n" +
  "            const p = cred['p'] ?? ''\n" +
  "            if (p.length > 0 && !CredentialStore.hasCredentialFor(domain)) {\n" +
  "              this.p47SaveDomain = domain\n" +
  "              this.p47SaveUser = u.length > 0 ? u : '(\u672a\u77e5\u7528\u6237\u540d)'\n" +
  "              this.p47SavePass = p\n" +
  "              this.p47SaveOpen = true\n" +
  "              console.info('[P47] save prompt: ' + domain + ' user=' + u)\n" +
  "            }\n" +
  "          } catch (e) {\n" +
  "            console.warn('[P47] cred parse fail')\n" +
  "          }\n" +
  "        }\n" +
  "      }).catch(() => {})\n" +
  "      if (tries >= 8) {\n" +
  "        clearInterval(timer)\n" +
  "      }\n" +
  "    }, 1500)\n" +
  "  }\n" +
  "\n" +
  "  /** P47-B: \u6267\u884c\u81ea\u52a8\u586b\u5145\uff08native setter + input/change \u4e8b\u4ef6\uff0c\u517c\u5bb9 React \u53d7\u63a7\u7ec4\u4ef6\uff09 */\n" +
  "  private p47DoFill(): void {\n" +
  "    const ctrl = this.getActiveController()\n" +
  "    if (!ctrl) {\n" +
  "      return\n" +
  "    }\n" +
  "    const u = JSON.stringify(this.p47FillUser)\n" +
  "    const p = JSON.stringify(this.p47FillPass)\n" +
  "    const js = \"(function(){function sv(el,v){var pr=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');if(pr&&pr.set){pr.set.call(el,v)}else{el.value=v}el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))}var un=document.querySelector('input[type=email]')||document.querySelector('input[type=text]')||document.querySelector('input:not([type])');var pw=document.querySelector('input[type=password]');if(!pw)return 'no-pw';if(un){sv(un,'\" + u + \"')}sv(pw,'\" + p + \"');return 'ok'})()\"\n" +
  "    ctrl.runJavaScript(js).then((r: string) => {\n" +
  "      console.info('[P47] fill result: ' + r)\n" +
  "      this.p47ShowFillBar = false\n" +
  "    }).catch((e: Object) => {\n" +
  "      console.error('[P47] fill fail: ' + e)\n" +
  "    })\n" +
  "  }\n" +
  "\n" +
  "  private p47DismissFill(): void {\n" +
  "    this.p47ShowFillBar = false\n" +
  "  }\n" +
  "\n" +
  "  /** P47-B: \u4fdd\u5b58\u5355\u51ed\u51ed\u636e */\n" +
  "  private p47DoSave(): void {\n" +
  "    const user = this.p47SaveUser === '(\u672a\u77e5\u7528\u6237\u540d)' ? '' : this.p47SaveUser\n" +
  "    CredentialStore.add(this.p47SaveDomain, user, this.p47SavePass).then(() => {\n" +
  "      console.info('[P47] credential saved: ' + this.p47SaveDomain)\n" +
  "      this.p47SaveOpen = false\n" +
  "    })\n" +
  "  }\n" +
  "\n" +
  "  /** \u65b0\u5efa\u7a7a\u767d\u6807\u7b7e\u9875\uff08\u5207\u5230 dashboard \u6001\uff09 */",
  'methods');

saveFile(ETS + '/pages/BrowserShell.ets', sh, shF.eol);
console.log('BrowserShell.ets patched, eol=' + JSON.stringify(shF.eol), sh.length);

/* ---------- 2. ChromeWidgets.ets ---------- */
const cwF = loadFile(ETS + '/components/ChromeWidgets.ets');
let cw = cwF.text;
cw = patch(cw, "    { icon: $rawfile('ic_download.svg'), label: '\u4e0b\u8f7d', action: 'downloads' }\n  ]",
  "    { icon: $rawfile('ic_download.svg'), label: '\u4e0b\u8f7d', action: 'downloads' },\n" +
  "    { icon: $rawfile('ic_key.svg'), label: '\u5bc6\u7801\u7ba1\u7406\u5668', action: 'passwords' }\n  ]",
  'menu-pw');
cw = patch(cw, "    { icon: $rawfile('ic_settings.svg'), label: '\u8bbe\u7f6e', action: 'settings' },",
  "    { icon: $rawfile('ic_bug.svg'), label: '\u5f00\u53d1\u8005\u5de5\u5177', action: 'devtools' },\n" +
  "    { icon: $rawfile('ic_settings.svg'), label: '\u8bbe\u7f6e', action: 'settings' },",
  'menu-dt');
saveFile(ETS + '/components/ChromeWidgets.ets', cw, cwF.eol);
console.log('ChromeWidgets.ets patched, eol=' + JSON.stringify(cwF.eol), cw.length);

/* ---------- 3. main_pages.json ---------- */
const mpPath = PROJ + '/entry/src/main/resources/base/profile/main_pages.json';
const mp = JSON.parse(fs.readFileSync(mpPath, 'utf8'));
for (const p of ['pages/PasswordsPage', 'pages/DevToolsPage']) {
  if (!mp.src.includes(p)) mp.src.push(p);
}
fs.writeFileSync(mpPath, JSON.stringify(mp, null, 2) + '\r\n');
console.log('main_pages.json entries:', mp.src.length);
console.log('ALL PATCHES OK');
