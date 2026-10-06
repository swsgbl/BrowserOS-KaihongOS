// bundleName 更换：com.oneaiterm.terminal -> com.browseros.kaihong
// 步骤 1-4 精确替换，全部 assert count，任何一步不满足即抛错（不写盘）
const fs = require('fs');
const ROOT = 'D:/BrowserOS - KaihongOS';

function replaceExact(file, from, to, expect) {
  const p = ROOT + '/' + file;
  let s = fs.readFileSync(p, 'utf8');
  const n = s.split(from).length - 1;
  if (n !== expect) throw new Error(`${file}: expected ${expect} occurrence(s) of ${JSON.stringify(from)}, found ${n} - ABORT`);
  s = s.split(from).join(to);
  fs.writeFileSync(p, s);
  console.log(`OK ${file}: replaced ${n}x ${JSON.stringify(from)}`);
}

// 1. app.json5 bundleName
replaceExact('AppScope/app.json5', '"bundleName": "com.oneaiterm.terminal"', '"bundleName": "com.browseros.kaihong"', 1);

// 2. deploy 脚本 aa start 命令
replaceExact('deploy_hap.py', 'aa start -a EntryAbility -b com.oneaiterm.terminal', 'aa start -a EntryAbility -b com.browseros.kaihong', 1);
replaceExact('deploy_p1.py', 'aa start -a EntryAbility -b com.oneaiterm.terminal', 'aa start -a EntryAbility -b com.browseros.kaihong', 1);

// 3. DEVPLAN.md 仅第 21 行（流水线命令）；第 10 行历史指令小节保留
{
  const p = ROOT + '/DEVPLAN.md';
  const lines = fs.readFileSync(p, 'utf8').split('\n');
  const idx = lines.findIndex(l => l.includes('aa start -a EntryAbility -b com.oneaiterm.terminal'));
  if (idx !== 20) throw new Error(`DEVPLAN.md: aa start line expected at line 21 (0-based 20), found ${idx + 1} - ABORT`);
  lines[idx] = lines[idx].split('com.oneaiterm.terminal').join('com.browseros.kaihong');
  fs.writeFileSync(p, lines.join('\n'));
  console.log('OK DEVPLAN.md line 21: aa start -> com.browseros.kaihong');
}

// 4. 删 entry string.json 冗余 app_name（只留 AppScope 一处）
{
  const p = ROOT + '/entry/src/main/resources/base/element/string.json';
  const j = JSON.parse(fs.readFileSync(p, 'utf8'));
  const before = j.string.length;
  j.string = j.string = j.string.filter(e => e.name !== 'app_name');
  if (before - j.string.length !== 1) throw new Error(`entry string.json: expected exactly 1 app_name entry, removed ${before - j.string.length} - ABORT`);
  fs.writeFileSync(p, JSON.stringify(j, null, 2) + '\n');
  console.log('OK entry string.json: app_name removed (module_desc/EntryAbility_* kept)');
}

console.log('ALL STEPS 1-4 DONE');
