/* P47 phase2: ChromeWidgets menu entries (incognito + zoom) */
const fs = require('fs');
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/components/ChromeWidgets.ets';
let s = fs.readFileSync(P, 'utf8');
const eol = s.includes('\r\n') ? '\r\n' : '\n';
s = s.replace(/\r\n/g, '\n');
function patch(src, o, n, tag) {
  const i = src.indexOf(o);
  if (i < 0) throw new Error('MISS ' + tag);
  if (src.indexOf(o, i + 1) >= 0) throw new Error('DUP ' + tag);
  return src.slice(0, i) + n + src.slice(i + o.length);
}
s = patch(s, "    { icon: $rawfile('ic_content_copy.svg'), label: '\u65b0\u7a97\u53e3', action: 'new_window' }\n  ]",
  "    { icon: $rawfile('ic_content_copy.svg'), label: '\u65b0\u7a97\u53e3', action: 'new_window' },\n" +
  "    { icon: $rawfile('ic_incognito.svg'), label: '\u65b0\u5efa\u65e0\u75d5\u6807\u7b7e\u9875', action: 'new_incognito' }\n  ]", 'incog');
s = patch(s, "    { icon: $rawfile('ic_bug.svg'), label: '\u5f00\u53d1\u8005\u5de5\u5177', action: 'devtools' },",
  "    { icon: $rawfile('ic_zoom_search.svg'), label: '\u653e\u5927', action: 'zoom_in' },\n" +
  "    { icon: $rawfile('ic_zoom_out.svg'), label: '\u7f29\u5c0f', action: 'zoom_out' },\n" +
  "    { icon: $rawfile('ic_reload.svg'), label: '\u91cd\u7f6e\u7f29\u653e', action: 'zoom_reset' },\n" +
  "    { icon: $rawfile('ic_bug.svg'), label: '\u5f00\u53d1\u8005\u5de5\u5177', action: 'devtools' },", 'zoom');
fs.writeFileSync(P, eol === '\r\n' ? s.replace(/\n/g, '\r\n') : s, 'utf8');
console.log('ChromeWidgets phase2 OK, incognito=' + s.includes('new_incognito') + ' zoom=' + s.includes('zoom_reset'));
