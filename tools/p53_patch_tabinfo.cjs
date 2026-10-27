// P53: TabInfo 加 profileType（CRLF 文件 node 补丁）
const fs = require('fs')
const P = 'D:/BrowserOS - KaihongOS/entry/src/main/ets/model/TabInfo.ets'
let t = fs.readFileSync(P, 'utf8')
let n = 0

function rep(oldStr, newStr, label) {
  const o = oldStr.replace(/\n/g, '\r\n')
  const nw = newStr.replace(/\n/g, '\r\n')
  if (!t.includes(o)) { console.error('MISS: ' + label); process.exit(1) }
  t = t.replace(o, nw); n++
}

// 1. interface 加字段
rep('  createdAt: number\n}',
    '  createdAt: number\n  profileType: string   // P53: default | incognito\n}', 'iface field')

// 2. class 加字段 + isIncognito()
rep('  createdAt: number = 0\n\n  constructor(',
    '  createdAt: number = 0\n  profileType: string = \'default\'   // P53\n\n  isIncognito(): boolean {\n    return this.profileType === \'incognito\'\n  }\n\n  constructor(', 'class field')

// 3. toJSON
rep('      createdAt: this.createdAt\n    }',
    '      createdAt: this.createdAt,\n      profileType: this.profileType\n    }', 'toJSON')

// 4. fromJSON
rep('    tab.createdAt = json.createdAt\n    return tab',
    '    tab.createdAt = json.createdAt\n    if (json.profileType !== undefined) {\n      tab.profileType = json.profileType\n    }\n    return tab', 'fromJSON')

fs.writeFileSync(P, t, 'utf8')
const v = fs.readFileSync(P, 'utf8')
if (!v.includes('profileType') || !v.includes('isIncognito()')) { console.error('VERIFY FAIL'); process.exit(1) }
console.log('OK: TabInfo patched (' + n + ' edits)')
