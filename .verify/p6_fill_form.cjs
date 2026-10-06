const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
const sh = (cmd) => console.log(execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 }).trim());
const sleep = (ms) => execSync(`ping -n ${Math.floor(ms / 1000) + 1} 127.0.0.1 >nul`, { shell: 'cmd.exe' });

// 点击代理名称输入框 → 输入
sh('uinput -T -c 1355 469'); sleep(1500);
sh("uinput -T -M 20 -m 0 -c 0 0 2>/dev/null; uitest uiInput inputText 1355 469 'p6demo'");
sleep(1200);
// 目标URL
sh('uinput -T -c 1355 506'); sleep(1200);
sh("uitest uiInput inputText 1355 506 'https://example.com'");
sleep(1200);
// 任务描述
sh('uinput -T -c 1355 544'); sleep(1200);
sh("uitest uiInput inputText 1355 544 'open the page and tell me the page title'");
sleep(1500);
console.log('--- dump inputs ---');
sh('uitest dumpLayout -p /data/local/tmp/p6_f.json');
execSync(`${HDC} -t ${T} file recv /data/local/tmp/p6_f.json .verify/p6_f.json`, { encoding: 'utf8' });
const c = require('fs').readFileSync('.verify/p6_f.json', 'utf8');
const hits = [];
function walk(n) { if (!n || typeof n !== 'object') return; const a = n.attributes || {}; if ((a.type || n.type) === 'TextInput') hits.push({ text: a.text, bounds: a.bounds }); (n.children || []).forEach(walk); }
const root = JSON.parse(c); Array.isArray(root) ? root.forEach(walk) : walk(root);
hits.forEach(h => console.log(JSON.stringify(h)));
