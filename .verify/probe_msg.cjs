const fs = require('fs');
const s = fs.readFileSync('D:/BrowserOS - KaihongOS/entry/src/main/ets/service/HttpMcpTransport.ets', 'utf8');
const i = s.indexOf("client.on('message'");
console.log(JSON.stringify(s.slice(i, i + 300)));
