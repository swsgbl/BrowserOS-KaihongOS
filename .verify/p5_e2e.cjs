const { execSync } = require('child_process');
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"';
const T = '127.0.0.1:15566';
function sh(label, cmd) {
  console.log('=== ' + label + ' ===');
  try {
    const out = execSync(`${HDC} -t ${T} shell "${cmd}"`, { encoding: 'utf8', maxBuffer: 30 * 1024 * 1024 });
    console.log(out.trim().slice(0, 4000));
    return out;
  } catch (e) { console.log('ERR ' + (e.stdout || e.message).toString().slice(0, 500)); return ''; }
}
const sleep = (ms) => execSync('ping -n ' + (ms / 1000 + 1).toFixed(0) + ' 127.0.0.1 >nul');

// layout dump helper: click by text keyword
function dumpLayout() {
  execSync(`${HDC} -t ${T} shell "uitest dumpLayout -p /data/local/tmp/p5_l.json"`, { encoding: 'utf8', maxBuffer: 30 * 1024 * 1024 });
  return execSync(`${HDC} -t ${T} shell "cat /data/local/tmp/p5_l.json"`, { encoding: 'utf8', maxBuffer: 30 * 1024 * 1024 });
}
function clickText(kw) {
  const j = dumpLayout();
  try {
    const obj = JSON.parse(j);
    const found = [];
    (function walk(n) {
      if (!n || typeof n !== 'object') return;
      const a = n.attributes || {};
      const txt = (a.text || '') + '';
      if (txt && txt.indexOf(kw) >= 0 && a.bounds) found.push({ txt, bounds: a.bounds });
      (n.children || []).forEach(walk);
    })(obj);
    if (found.length === 0) { console.log('clickText MISS: ' + kw); return false; }
    const b = found[0].bounds;
    const m = b.match(/([\d.]+),([\d.]+)\]\[([\d.]+),([\d.]+)/) || b.match(/\[?([\d.]+),([\d.]+)/);
    const x1 = parseFloat(b.split('][')[0].replace(/[\[\]]/g, '').split(',')[0]);
    const y1 = parseFloat(b.split('][')[0].replace(/[\[\]]/g, '').split(',')[1]);
    const x2 = parseFloat(b.split('][')[1].replace(/[\[\]]/g, '').split(',')[0]);
    const y2 = parseFloat(b.split('][')[1].replace(/[\[\]]/g, '').split(',')[1]);
    const cx = Math.round((x1 + x2) / 2), cy = Math.round((y1 + y2) / 2);
    console.log('clickText[' + kw + '] -> (' + cx + ',' + cy + ') "' + found[0].txt.slice(0, 30) + '"');
    execSync(`${HDC} -t ${T} shell "uinput -T -c ${cx} ${cy}"`, { encoding: 'utf8' });
    return true;
  } catch (e) { console.log('clickText ERR ' + e.message); return false; }
}
function inputText(t) {
  execSync(`${HDC} -t ${T} shell "uinput -T -M 400 240 -c 400 240 400 240"`, { encoding: 'utf8' });
  execSync(`${HDC} -t ${T} file send .verify\\p5_input.txt /data/local/tmp/p5_input.txt`, { encoding: 'utf8' });
  execSync(`${HDC} -t ${T} shell "cat /data/local/tmp/p5_input.txt | while read line; do uinput -T -k $line; done"`, { encoding: 'utf8' });
  sh('input', `uinput -T -k ${t}`);
}

const step = process.argv[2];
if (step === 'dump') {
  const j = dumpLayout();
  // print all text nodes
  try {
    const obj = JSON.parse(j);
    (function walk(n) {
      if (!n || typeof n !== 'object') return;
      const a = n.attributes || {};
      if (a.text) console.log(a.type + ' | ' + a.text.slice(0, 60) + ' | ' + a.bounds);
      (n.children || []).forEach(walk);
    })(obj);
  } catch (e) { console.log('parse err, raw head: ' + j.slice(0, 800)); }
} else if (step === 'click') {
  clickText(process.argv[3]);
} else if (step === 'clickxy') {
  sh('click', 'uinput -T -c ' + process.argv[3] + ' ' + process.argv[4]);
} else if (step === 'key') {
  sh('key', 'uinput -T -k ' + process.argv[3]);
} else if (step === 'type') {
  // type ASCII text into focused field (space-safe: quote whole cmd)
  sh('type', 'uinput -K -t "' + process.argv[3] + '"');
} else if (step === 'sleep') {
  sleep(parseInt(process.argv[3]));
} else if (step === 'inputs') {
  const j = dumpLayout();
  const obj = JSON.parse(j);
  (function walk(n) {
    if (!n || typeof n !== 'object') return;
    const a = n.attributes || {};
    if (a.type && (String(a.type).indexOf('TextInput') >= 0 || String(a.type).indexOf('TextArea') >= 0)) console.log(a.type + ' | ' + ((a.text || '') + '').slice(0, 40) + ' | ' + a.bounds);
    (n.children || []).forEach(walk);
  })(obj);
} else if (step === 'hilog') {
  sh('hilog', 'hilog -x | grep -E "' + process.argv[3] + '" | tail -n 80');
}
