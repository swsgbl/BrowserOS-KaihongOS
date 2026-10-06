const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const cmd = process.argv[2]; // hilog command to run on device, e.g. "hilog -x"
const filter = process.argv[3] || ''; // regex filter
const tailN = parseInt(process.argv[4] || '30', 10);
const out = execSync(`${HDC} -t 127.0.0.1:15566 shell "${cmd}"`, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
let lines = out.split('\n');
if (filter) {
  const re = new RegExp(filter, 'i');
  lines = lines.filter(l => re.test(l));
}
console.log(lines.slice(-tailN).join('\n'));
console.log(`[total ${out.split('\n').length} lines, matched ${lines.length}]`);
