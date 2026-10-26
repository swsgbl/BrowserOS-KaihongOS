/* Fix incognitoMode placement + catch types in BrowserShell */
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/pages/BrowserShell.ets';
let s = fs.readFileSync(P, 'utf8');
const eol = s.includes('\r\n') ? '\r\n' : '\n';
s = s.replace(/\r\n/g, '\n');
function rep(o, n, tag) {
  const i = s.indexOf(o);
  if (i < 0) { console.log('MISS: ' + tag); process.exit(1); }
  s = s.slice(0, i) + n + s.slice(i + o.length);
}

// 1. remove misplaced .incognitoMode() attribute
rep("          .incognitoMode(this.p47IncognitoTabs.has(tab.tabId))\n", "", 'rm-attr');

// 2. add incognitoMode into Web() constructor params
rep("Web({ src: 'about:blank', controller: this.getOrCreateController(tab.tabId) })",
    "Web({ src: 'about:blank', controller: this.getOrCreateController(tab.tabId), incognitoMode: this.p47IncognitoTabs.has(tab.tabId) })", 'ctor');

// 3. catch(e) -> catch(e: Object) in the onInterceptRequest block
rep("                DevToolsCollector.addNetwork(tab.tabId, req.getUrl(), req.getMethod(), hdr)\n              } catch (e) {",
    "                DevToolsCollector.addNetwork(tab.tabId, req.getUrl(), req.getMethod(), hdr)\n              } catch (e: Object) {", 'catch1');

fs.writeFileSync(P, eol === '\r\n' ? s.replace(/\n/g, '\r\n') : s, 'utf8');
console.log('incognito fix OK');
