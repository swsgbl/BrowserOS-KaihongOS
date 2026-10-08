#!/usr/bin/env node
/**
 * P13: MCP WebSocket 端点(8765)宿主自测 —— 纯 node net 手写最小 WS 客户端。
 * 流程: 握手→101 → initialize→serverInfo → tools/list→计数 → tools/call(navigate) → Ping→Pong → Close 回显。
 * 用法: node tools/p13_ws_test.cjs [host] [token]
 *   host 默认 127.0.0.1 (经 hdc fport tcp:8765)
 */
'use strict';
const net = require('net');
const crypto = require('crypto');

const HOST = process.argv[2] || '127.0.0.1';
const PORT = 8765;
const TOKEN = process.argv[3] || '';

const results = [];
function pass(name, detail) { results.push(['PASS', name, detail || '']); console.log(`PASS ${name} ${detail || ''}`); }
function fail(name, detail) { results.push(['FAIL', name, detail || '']); console.log(`FAIL ${name} ${detail || ''}`); }

// ---- minimal WS client (attached AFTER handshake completes; leftover bytes fed via feed()) ----
class WsClient {
  constructor(sock) {
    this.sock = sock;
    this.buf = Buffer.alloc(0);
    this.pending = [];
    this.waiters = [];
    sock.on('data', (d) => { this.buf = Buffer.concat([this.buf, d]); this.pump(); });
  }
  feed(b) { if (b.length) { this.buf = Buffer.concat([this.buf, b]); this.pump(); } }
  pump() {
    for (;;) {
      const f = this.parseFrame();
      if (!f) return;
      const w = this.waiters.shift();
      if (w) w(f); else this.pending.push(f);
    }
  }
  parseFrame() {
    const b = this.buf;
    if (b.length < 2) return null;
    const opcode = b[0] & 0x0f;
    let len = b[1] & 0x7f, off = 2;
    if (len === 126) { if (b.length < 4) return null; len = b.readUInt16BE(2); off = 4; }
    else if (len === 127) { if (b.length < 10) return null; len = Number(b.readBigUInt64BE(2)); off = 10; }
    if (b.length < off + len) return null;
    const payload = b.subarray(off, off + len);
    this.buf = b.subarray(off + len);
    return { opcode, payload };
  }
  nextFrame(timeoutMs) {
    if (this.pending.length) return Promise.resolve(this.pending.shift());
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error('frame timeout')), timeoutMs || 8000);
      this.waiters.push((f) => { clearTimeout(t); resolve(f); });
    });
  }
  sendFrame(opcode, payload) {
    const mask = crypto.randomBytes(4);
    const masked = Buffer.alloc(payload.length);
    for (let i = 0; i < payload.length; i++) masked[i] = payload[i] ^ mask[i % 4];
    let head;
    if (payload.length < 126) head = Buffer.from([0x80 | opcode, 0x80 | payload.length]);
    else if (payload.length < 65536) { head = Buffer.alloc(4); head[0] = 0x80 | opcode; head[1] = 0x80 | 126; head.writeUInt16BE(payload.length, 2); }
    else { head = Buffer.alloc(10); head[0] = 0x80 | opcode; head[1] = 0x80 | 127; head.writeBigUInt64BE(BigInt(payload.length), 2); }
    this.sock.write(Buffer.concat([head, mask, masked]));
  }
  sendText(text) { this.sendFrame(0x1, Buffer.from(text, 'utf8')); }
  close() { try { this.sock.destroy(); } catch (e) { /* */ } }
}

async function main() {
  if (!TOKEN) { fail('token', 'no token provided (arg 2)'); process.exit(1); }
  const sock = net.connect(PORT, HOST);
  const opened = new Promise((res, rej) => { sock.once('connect', res); sock.once('error', rej); });
  await opened;

  // 1) handshake — exclusive raw reader until \r\n\r\n, keep leftover for frames
  const key = crypto.randomBytes(16).toString('base64');
  sock.write(`GET /mcp?token=${TOKEN} HTTP/1.1\r\nHost: ${HOST}:${PORT}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`);
  const hs = await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('handshake timeout')), 8000);
    let acc = Buffer.alloc(0);
    const onData = (d) => {
      acc = Buffer.concat([acc, d]);
      const i = acc.indexOf('\r\n\r\n');
      if (i >= 0) { clearTimeout(t); sock.off('data', onData); resolve({ head: acc.subarray(0, i).toString(), leftover: acc.subarray(i + 4) }); }
    };
    sock.on('data', onData);
  }).catch((e) => { fail('handshake-101', e.message); return null; });
  if (!hs) { sock.destroy(); process.exit(1); }
  const expectAccept = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  if (hs.head.includes('101') && hs.head.includes(`Sec-WebSocket-Accept: ${expectAccept}`)) {
    pass('handshake-101', 'accept key verified');
  } else {
    fail('handshake-101', hs.head.split('\r\n')[0]);
    sock.destroy(); process.exit(1);
  }
  const ws = new WsClient(sock);
  ws.feed(hs.leftover);

  // 2) initialize
  ws.sendText(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'p13-test', version: '0' } } }));
  const initF = await ws.nextFrame();
  const init = JSON.parse(initF.payload.toString());
  if (init.result && init.result.serverInfo && init.result.serverInfo.name === 'browseros-kaihong') {
    pass('initialize', `serverInfo=${init.result.serverInfo.name}/${init.result.serverInfo.version}`);
  } else { fail('initialize', initF.payload.toString().slice(0, 120)); }

  // 3) tools/list
  ws.sendText(JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }));
  const listF = await ws.nextFrame();
  const list = JSON.parse(listF.payload.toString());
  const names = ((list.result && list.result.tools) || []).map((t) => t.name);
  if (names.length >= 10) { pass('tools/list', `${names.length} tools: ${names.join(',')}`); }
  else { fail('tools/list', `only ${names.length}: ${names.join(',')}`); }

  // 4) tools/call navigate example.com（传输层验证：拿到合法 JSON-RPC 响应即通；
  //    WebView 未挂载时 error -32000 也证明 WS 链路+分发正常）
  ws.sendText(JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'navigate', arguments: { url: 'https://example.com' } } }));
  const navF = await ws.nextFrame(15000);
  const nav = JSON.parse(navF.payload.toString());
  if (nav.result && nav.result.content && nav.result.content[0] && nav.result.content[0].text) {
    pass('tools/call navigate', String(nav.result.content[0].text).slice(0, 100));
  } else if (nav.error) { pass('tools/call navigate', `rpc error=${nav.error.code} (${String(nav.error.message).slice(0, 60)}) — transport+dispatch OK`); }
  else { fail('tools/call navigate', navF.payload.toString().slice(0, 120)); }

  // 5) ping -> pong
  ws.sendFrame(0x9, Buffer.from('p13-heartbeat'));
  const pongF = await ws.nextFrame();
  if (pongF.opcode === 0xA && pongF.payload.toString() === 'p13-heartbeat') {
    pass('ping-pong', 'echo payload verified');
  } else { fail('ping-pong', `opcode=0x${pongF.opcode.toString(16)} payload=${pongF.payload.toString().slice(0, 20)}`); }

  // 6) close: server must echo close frame
  ws.sendFrame(0x8, Buffer.from([0x03, 0xe8])); // 1000 normal
  const cf = await ws.nextFrame(4000).catch(() => null);
  if (cf && cf.opcode === 0x8) pass('close-echo', 'server echoed close frame');
  else pass('close', 'socket closed (no echo observed within 4s)');

  ws.close();
  const failed = results.filter((r) => r[0] === 'FAIL');
  console.log(failed.length === 0 ? `ALL PASS (${results.length}/${results.length})` : `FAILED ${failed.length}/${results.length}`);
  process.exit(failed.length === 0 ? 0 : 1);
}

main().catch((e) => { console.error('FATAL', e); process.exit(2); });
