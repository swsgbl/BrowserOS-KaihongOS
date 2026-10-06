const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
const sleep = (ms) => execSync(`ping -n ${Math.floor(ms / 1000) + 1} 127.0.0.1 >nul`, { shell: 'cmd.exe' });
const log = () => execSync(`${HDC} -t ${T} shell "hilog -x | grep -E 'AgentEngine|SessionManager|onPageEnd' | tail -40"`, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
// 轮询最多 ~120s 等 COMPLETED
for (let i = 0; i < 12; i++) {
  sleep(10000);
  const out = log();
  const lines = out.split('\n').filter(l => /task complete|COMPLETED|task finished|final|screenshots|capture/.test(l));
  if (lines.length) {
    console.log('=== poll ' + i + ' ===');
    lines.forEach(l => console.log(l.trim()));
  }
  if (/task complete|COMPLETED/.test(out)) { console.log('=== AGENT COMPLETED ==='); break; }
}
// 最终全量
console.log('=== final tail ===');
console.log(log());
