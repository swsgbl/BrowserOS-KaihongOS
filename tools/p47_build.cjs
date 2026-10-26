const { execSync } = require('child_process');
try {
  execSync('hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug --no-daemon',
    { cwd: '.', encoding: 'utf8', timeout: 300000, maxBuffer: 20 * 1024 * 1024, stdio: 'pipe' });
  console.log('BUILD OK');
} catch (e) {
  const out = (e.stdout || '') + (e.stderr || '');
  const msgs = out.split('\n').filter(l => l.includes('Error Message'));
  console.log(msgs.slice(0, 12).join('\n') || out.split('\n').slice(-10).join('\n'));
}
