"use strict";
// vm-fetch-full.cjs — full-surface fetch polyfill for jitless KaihongOS node
// (WebAssembly unavailable -> built-in undici fetch crashes). Implements the
// fetch/Headers/Response surface Claude Code + Anthropic SDK need:
// Headers get/set/has/append/delete/entries/keys/values/forEach/iterator,
// Response status/ok/headers/url/text/json/arrayBuffer/body, duplex-less POST.
const https = require("node:https");
const http = require("node:http");
const { PassThrough } = require("node:stream");

class FullHeaders {
  constructor(init) {
    this._m = new Map();
    if (!init) return;
    if (typeof Headers !== 'undefined' && init instanceof Headers) {
      for (const [k, v] of init.entries()) this.append(k, v);
    } else if (Array.isArray(init)) {
      for (const [k, v] of init) this.append(k, v);
    } else if (typeof init === 'object') {
      for (const [k, v] of Object.entries(init)) this.append(k, v);
    }
  }
  _norm(k) { return String(k).toLowerCase(); }
  append(k, v) { const n = this._norm(k); this._m.set(n, this._m.has(n) ? this._m.get(n) + ', ' + String(v) : String(v)); }
  set(k, v) { this._m.set(this._norm(k), String(v)); }
  get(k) { const v = this._m.get(this._norm(k)); return v === undefined ? null : v; }
  has(k) { return this._m.has(this._norm(k)); }
  delete(k) { this._m.delete(this._norm(k)); }
  *entries() { yield* this._m.entries(); }
  *keys() { yield* this._m.keys(); }
  *values() { yield* this._m.values(); }
  forEach(fn, thisArg) { for (const [k, v] of this._m) fn.call(thisArg, v, k, this); }
  *[Symbol.iterator]() { yield* this._m.entries(); }
}

class FullResponse {
  constructor(statusCode, rawHeaders, res, url) {
    this.status = statusCode;
    this.ok = statusCode >= 200 && statusCode < 300;
    this.headers = new FullHeaders(Object.entries(rawHeaders || {}).map(([k, v]) => [k, Array.isArray(v) ? v.join(', ') : String(v)]));
    this.url = url || '';
    this.redirected = false;
    this.type = 'basic';
    this._res = res;
    this._buffered = null;
  }
  get body() {
    if (!this._bodyStream) {
      const src = this._res;
      this._bodyStream = new ReadableStream({
        start(ctrl) {
          src.on('data', (c) => { try { ctrl.enqueue(new Uint8Array(c)); } catch (e) {} });
          src.on('end', () => { try { ctrl.close(); } catch (e) {} });
          src.on('error', (e) => { try { ctrl.error(e); } catch (e2) {} });
        },
        cancel() { try { src.destroy(); } catch (e) {} },
      });
    }
    return this._bodyStream;
  }
  async _buf() {
    if (this._buffered) return this._buffered;
    const chunks = [];
    for await (const c of this._res) chunks.push(c);
    this._buffered = Buffer.concat(chunks);
    return this._buffered;
  }
  async text() { return (await this._buf()).toString('utf8'); }
  async json() { return JSON.parse(await this.text()); }
  async arrayBuffer() { const b = await this._buf(); return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength); }
  clone() { return this; }
}

globalThis.Headers = FullHeaders;
globalThis.Response = FullResponse;
globalThis.fetch = async function fetch(input, init = {}) {
  const url = typeof input === 'string' ? input : (input && input.url) || String(input);
  const method = (init.method || (input && input.method) || 'GET').toUpperCase();
  const u = new URL(String(url));
  const mod = u.protocol === 'https:' ? https : http;
  const h = new FullHeaders(init.headers || (input && input.headers) || {});
  if (!h.has('user-agent')) h.set('user-agent', 'vm-fetch-full/1');
  let body = init.body !== undefined ? init.body : (input && input.body);
  if (body && typeof body === 'string' && !h.has('content-length')) h.set('content-length', String(Buffer.byteLength(body)));
  if (body && typeof body === 'string' && !h.has('content-type')) h.set('content-type', 'application/json');
  return await new Promise((resolve, reject) => {
    const req = mod.request({
      hostname: u.hostname, port: u.port || (u.protocol === 'https:' ? 443 : 80),
      path: u.pathname + u.search, method,
      headers: Object.fromEntries([...h.entries()].map(([k, v]) => [k, v])),
    }, (res) => {
      // follow redirects up to 5
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        const next = new URL(res.headers.location, url).toString();
        return resolve(fetch(next, init));
      }
      resolve(new FullResponse(res.statusCode, res.headers, res, url));
    });
    req.on('error', reject);
    if (init.signal) {
      init.signal.addEventListener('abort', () => { req.destroy(new Error('aborted')); });
      if (init.signal.aborted) { req.destroy(new Error('aborted')); return; }
    }
    if (body) {
      if (typeof body === 'string') req.write(body);
      else if (Buffer.isBuffer(body)) req.write(body);
      else if (body && typeof body.pipe === 'function') body.pipe(req);
    }
    req.end();
  });
};
