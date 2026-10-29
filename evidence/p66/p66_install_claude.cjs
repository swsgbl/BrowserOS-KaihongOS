#!/bin/node
// Find the newest @anthropic-ai/claude-code version whose npm package is PURE JS (bin -> cli.js),
// download and extract it, smoke test under jitless+vm-fetch.
const https = require('https');
const { execSync } = require('child_process');
const fs = require('fs');

const DEST = '/data/local/tmp/claude-code-install';
const POLYFILL = '/data/local/home/.local/hmharness/vm-fetch.cjs';

function get(urlStr, binary, redirects) {
  return new Promise((resolve, reject) => {
    if ((redirects || 0) > 5) return reject(new Error('too many redirects'));
    const u = new URL(urlStr);
    const req = https.get({ hostname: u.hostname, path: u.pathname + u.search, headers: { 'User-Agent': 'p66-installer' }, timeout: 30000 }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) { res.resume(); return resolve(get(res.headers.location, binary, (redirects || 0) + 1)); }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: binary ? Buffer.concat(chunks) : Buffer.concat(chunks).toString('utf8') }));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

(async () => {
  console.log('[1] metadata...');
  const meta = await get('https://registry.npmmirror.com/@anthropic-ai%2fclaude-code');
  const j = JSON.parse(meta.body);
  const vers = Object.keys(j.versions || {}).sort((a, b) => (a < b ? 1 : -1)); // newest first (semver-ish string sort)
  // pick newest whose bin.claude is a .js file (pure JS package)
  let pick = null;
  for (const v of vers.slice(0, 60)) {
    const bin = j.versions[v].bin || {};
    const bc = typeof bin === 'string' ? bin : (bin.claude || bin['claude-code'] || '');
    if (/\.c?js$/.test(bc)) { pick = { v, bc }; break; }
  }
  if (!pick) { console.log('no pure-JS version found in latest 60'); process.exit(1); }
  console.log('newest pure-JS version:', pick.v, 'bin:', pick.bc);
  const tarUrl = 'https://registry.npmmirror.com/@anthropic-ai/claude-code/-/claude-code-' + pick.v + '.tgz';
  console.log('[2] downloading', tarUrl);
  const t0 = Date.now();
  const tgz = await get(tarUrl, true);
  if (tgz.status !== 200) { console.log('download FAIL', tgz.status); process.exit(1); }
  fs.rmSync(DEST, { recursive: true, force: true });
  fs.mkdirSync(DEST, { recursive: true });
  fs.writeFileSync(DEST + '/pkg.tgz', tgz.body);
  console.log('downloaded', Math.round(tgz.body.length / 1024), 'KB in', Date.now() - t0, 'ms');
  execSync('cd ' + DEST + ' && tar xzf pkg.tgz');
  const binPath = DEST + '/package/' + pick.bc;
  console.log('[3] smoke test under jitless+vm-fetch...');
  try {
    const out = execSync('NODE_OPTIONS="--jitless --require ' + POLYFILL + '" node ' + binPath + ' --version', { timeout: 180000, encoding: 'utf8' });
    console.log('VERSION_OUTPUT:', JSON.stringify(String(out).trim().slice(0, 120)));
    console.log('PURE-JS CLAUDE CODE RUNS ON VM');
  } catch (e) {
    console.log('SMOKE FAILED');
    console.log(String(e.stderr || e.stdout || e.message).slice(0, 700));
    process.exit(2);
  }
})().catch((e) => { console.log('FATAL:', e.message); process.exit(1); });
