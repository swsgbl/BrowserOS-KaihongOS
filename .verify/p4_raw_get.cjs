const net = require('net');

// Raw TCP: handcrafted GET with proper CRLFCRLF
const req = 'GET /mcp?token=abc HTTP/1.1\r\nHost: 127.0.0.1:9222\r\nConnection: close\r\n\r\n';

const sock = net.connect(9222, '127.0.0.1', () => {
  console.log('[probe] connected, sending GET (' + req.length + 'B)');
  sock.write(req);
});
let got = Buffer.alloc(0);
sock.on('data', (d) => { got = Buffer.concat([got, d]); });
sock.on('close', () => {
  console.log('[probe] closed. received ' + got.length + 'B');
  if (got.length > 0) console.log('[probe] response head: ' + got.toString('utf8').slice(0, 200));
});
sock.on('error', (e) => console.log('[probe] error: ' + e.message));
setTimeout(() => {
  console.log('[probe] 5s window over, bytes=' + got.length);
  if (got.length > 0) console.log('[probe] head: ' + got.toString('utf8').slice(0, 250));
  sock.destroy();
  process.exit(0);
}, 5000);
