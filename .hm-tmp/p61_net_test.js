// P61 step1b: VM -> HOST relay connectivity test (native http, fetch is broken: no WebAssembly)
const http = require('http');

function get(host, port, path) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host, port, path, timeout: 8000 }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

(async () => {
  // 1. VM -> HOST relay
  try {
    const r = await get('192.168.161.1', 19223, '/health');
    console.log('VM_TO_HOST_RELAY_OK:', r.status, r.body.slice(0, 120));
  } catch (e) {
    console.log('VM_TO_HOST_RELAY_FAIL:', e.message);
  }
  // 2. VM -> browser MCP (loopback)
  try {
    const r = await get('127.0.0.1', 9222, '/mcp');
    console.log('VM_TO_MCP_OK: status', r.status, 'body:', r.body.slice(0, 120));
  } catch (e) {
    console.log('VM_TO_MCP_FAIL:', e.message);
  }
})();
