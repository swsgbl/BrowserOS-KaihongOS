/* Fix intercept request API names + catch clause */
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
rep("                DevToolsCollector.addNetwork(tab.tabId, req.getUrl(), req.getMethod(), hdr)",
    "                DevToolsCollector.addNetwork(tab.tabId, req.getRequestUrl(), req.getRequestMethod(), hdr)", 'api');
rep("              } catch (e: Object) {\n                // \u8bb0\u5f55\u5931\u8d25\u4e0d\u963b\u65ad\u52a0\u8f7d",
    "              } catch (e) {\n                // \u8bb0\u5f55\u5931\u8d25\u4e0d\u963b\u65ad\u52a0\u8f7d", 'catch');
fs.writeFileSync(P, eol === '\r\n' ? s.replace(/\n/g, '\r\n') : s, 'utf8');
console.log('intercept API fixed');
