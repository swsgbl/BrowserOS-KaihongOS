// P61: HOST-side LLM relay for VM-resident AI agents.
// VM (192.168.161.0/24) can reach the VMware NAT gateway (this host, 192.168.161.1)
// but cannot reach external APIs directly. This relay forwards
// POST /v1/*  ->  https://apihub.agnes-ai.com/v1/*
// Zero dependencies: Node.js native http/https only.
// Usage: node tools/llm_relay.js   (listens on 0.0.0.0:19223)

const http = require('http');
const https = require('https');
const { URL } = require('url');

const PORT = 19223;
const UPSTREAM = 'https://apihub.agnes-ai.com';
const upstreamUrl = new URL(UPSTREAM);

function forward(req, res) {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const path = req.url.replace(/^\/v1/, '/v1');
    const headers = {
      'Content-Type': req.headers['content-type'] || 'application/json',
      'Content-Length': body.length,
    };
    if (req.headers['authorization']) headers['Authorization'] = req.headers['authorization'];
    if (req.headers['accept']) headers['Accept'] = req.headers['accept'];

    const opts = {
      hostname: upstreamUrl.hostname,
      port: 443,
      path: path,
      method: req.method,
      headers: headers,
    };

    const t0 = Date.now();
    const up = https.request(opts, (ur) => {
      res.writeHead(ur.statusCode, {
        'Content-Type': ur.headers['content-type'] || 'application/json',
        'Access-Control-Allow-Origin': '*',
      });
      ur.pipe(res);
      ur.on('end', () => {
        console.log(`[${new Date().toISOString()}] ${req.method} ${path} -> ${ur.statusCode} (${Date.now() - t0}ms, ${body.length}B in)`);
      });
    });
    up.on('error', (e) => {
      console.error(`[${new Date().toISOString()}] upstream error: ${e.message}`);
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: `relay upstream error: ${e.message}` } }));
    });
    up.write(body);
    up.end();
  });
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && (req.url === '/' || req.url === '/health')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', upstream: UPSTREAM, pid: process.pid }));
    return;
  }
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Accept',
    });
    res.end();
    return;
  }
  forward(req, res);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[llm_relay] listening on 0.0.0.0:${PORT} -> ${UPSTREAM}`);
  console.log(`[llm_relay] VM clients should use http://192.168.161.1:${PORT}/v1`);
});
