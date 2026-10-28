// P57: run harness_compat_test.py N times, collect FAIL lines
const { execSync } = require('child_process');
const runs = process.argv[2] ? parseInt(process.argv[2]) : 3;
for (let i = 1; i <= runs; i++) {
  console.log('--- run ' + i + '/' + runs + ' ---');
  try {
    const out = execSync('C:\\Users\\hongfu\\AppData\\Local\\mise\\shims\\python.exe tools\\harness_compat_test.py 2>&1', 
      { cwd: 'D:\\BrowserOS - KaihongOS', encoding: 'utf8', timeout: 280000, maxBuffer: 10 * 1024 * 1024 });
    (out.match(/\[FAIL\][^\n]*/g) || []).forEach(l => console.log(l));
    (out.match(/== harness_compat_test[^\n]*/g) || []).forEach(l => console.log(l));
  } catch (e) {
    const out = (e.stdout || '') + (e.stderr || '');
    (out.match(/\[FAIL\][^\n]*/g) || []).forEach(l => console.log(l));
    (out.match(/== harness_compat_test[^\n]*/g) || []).forEach(l => console.log(l));
  }
}
