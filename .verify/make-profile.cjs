// 从 VM 拉回的原始 profile 精确改: bundle-name + uuid + not-after
const fs = require('fs');
const p = 'D:/BrowserOS - KaihongOS/.verify/profile-original.json';
let s = fs.readFileSync(p, 'utf8');

// 1. bundle-name (原 JSON 该行有尾随空格, 用宽松单次匹配)
const m = s.match(/"bundle-name":\s*"com\.oneaiterm\.terminal"/);
if (!m) throw new Error('bundle-name pattern not found - ABORT');
s = s.replace(m[0], '"bundle-name": "com.browseros.kaihong"');

// 2. uuid 换新
const mu = s.match(/"uuid":\s*"[0-9a-f-]+"/);
if (!mu) throw new Error('uuid pattern not found - ABORT');
s = s.replace(mu[0], '"uuid":"6b3a8c1d-7e42-4f59-8a61-b2c9d0e4f7a3"');

// 3. not-after 拉长到 2100 年 (4102444800)
const mv = s.match(/"not-after":\s*(\d+)/);
if (!mv) throw new Error('not-after pattern not found - ABORT');
s = s.replace(mv[0], '"not-after":4102444800');

fs.writeFileSync('D:/BrowserOS - KaihongOS/.verify/profile-browseros.json', s);
// 复读验证
const chk = JSON.parse(fs.readFileSync('D:/BrowserOS - KaihongOS/.verify/profile-browseros.json', 'utf8'));
console.log('bundle-name:', chk['bundle-info']['bundle-name']);
console.log('uuid:', chk.uuid);
console.log('not-after:', chk.validity['not-after']);
console.log('type:', chk.type, '| apl:', chk['bundle-info'].apl);
console.log('PROFILE JSON OK');
