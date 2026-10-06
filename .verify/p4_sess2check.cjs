const fs = require('fs');
const j = fs.readFileSync('D:\\BrowserOS - KaihongOS\\.verify\\p4_session2.json', 'utf8');
const o = JSON.parse(j);
console.log('sessionId=' + o.sessionId);
console.log('operationLogs=' + o.operationLogs.length + ' screenshots=' + o.screenshots.length + ' urlSequence=' + o.urlSequence.length);
if (o.screenshots.length > 0) {
  const s = o.screenshots[0];
  console.log('shot0 keys=' + Object.keys(s).join(','));
  console.log('shot0 dataPrefix=' + (s.data ? s.data.substring(0, 40) : 'none') + ' len=' + (s.data ? s.data.length : 0));
  console.log('shot0 url=' + (s.url || s.pageUrl || ''));
}
if (o.urlSequence.length > 0) console.log('urls=' + o.urlSequence.join(','));
