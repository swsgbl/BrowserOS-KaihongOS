const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
const sh = (cmd) => console.log(execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 }).trim());
const sleep = (ms) => execSync(`ping -n ${Math.floor(ms / 1000) + 1} 127.0.0.1 >nul`, { shell: 'cmd.exe' });

// 找创建代理按钮
execSync(`${HDC} -t ${T} shell "uitest dumpLayout -p /data/local/tmp/p6_g.json"`, { encoding: 'utf8' });
execSync(`${HDC} -t ${T} file recv /data/local/tmp/p6_g.json .verify/p6_g.json`, { encoding: 'utf8' });
const c = require('fs').readFileSync('.verify/p6_g.json', 'utf8');
const root = JSON.parse(c);
let btn = null;
function walk(n) {
  if (!n || typeof n !== 'object') return;
  const a = n.attributes || {};
  if (a.text === '创建代理' && !btn) btn = a.bounds;
  (n.children || []).forEach(walk);
}
Array.isArray(root) ? root.forEach(walk) : walk(root);
console.log('创建代理 button bounds:', btn);
if (btn) {
  const m = btn.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
  const x = Math.round((+m[1] + +m[3]) / 2), y = Math.round((+m[2] + +m[4]) / 2);
  console.log('click at', x, y);
  sh(`uinput -T -c ${x} ${y}`);
  sleep(2000);
  console.log('--- agent created, check hilog soon ---');
}
