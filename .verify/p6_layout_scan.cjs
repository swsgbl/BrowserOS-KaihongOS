const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
execSync(`${HDC} -t ${T} file recv /data/local/tmp/p6_layout.json .verify/p6_layout.json`, { encoding: 'utf8' });
const c = require('fs').readFileSync('.verify/p6_layout.json', 'utf8');
const hits = [];
function walk(n) {
  if (!n || typeof n !== 'object') return;
  const a = n.attributes || {};
  if ((a.type || n.type) === 'TextInput') hits.push({ text: a.text, bounds: a.bounds });
  (n.children || []).forEach(walk);
}
const root = JSON.parse(c);
Array.isArray(root) ? root.forEach(walk) : walk(root);
console.log('TextInput count:', hits.length);
hits.forEach(h => console.log(JSON.stringify(h)));
// 找 创建代理 按钮和 placeholder 文本
const texts = [];
function walk2(n) {
  if (!n || typeof n !== 'object') return;
  const a = n.attributes || {};
  if (a.text) texts.push(a.text);
  (n.children || []).forEach(walk2);
}
Array.isArray(root) ? root.forEach(walk2) : walk2(root);
console.log('--- texts containing 代理/名称/URL/任务 ---');
texts.filter(t => /代理|名称|URL|任务|placeholder/i.test(t)).forEach(t => console.log(t));
