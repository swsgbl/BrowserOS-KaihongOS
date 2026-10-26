// P50 步骤驱动器: dumpLayout 找控件坐标
const { execSync } = require('child_process')
const HDC = 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe'
const T = '192.168.161.137:10178'

function hdc(...args) {
  return execSync('"' + HDC + '" -t ' + T + ' ' + args.join(' '), { maxBuffer: 20e6 }).toString()
}

// dumpLayout 到设备再拉回
hdc('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/p50_layout.json')
hdc('file', 'recv', '/data/local/tmp/p50_layout.json', 'D:/BrowserOS - KaihongOS/evidence/p50/layout.json')

const j = JSON.parse(require('fs').readFileSync('D:/BrowserOS - KaihongOS/evidence/p50/layout.json', 'utf8'))

// 递归找匹配属性串的节点
function walk(n, path, out) {
  const attrs = n.attributes || {}
  const rect = attrs['rect'] || ''
  const hit = (kws) => {
    const s = JSON.stringify(n)
    return kws.every(k => s.includes(k))
  }
  out.push({ depth: path.split('/').length, type: n.type, rect, id: attrs['id'], text: attrs['text'], key: Object.keys(attrs).join(',') })
  for (const c of (n.children || [])) walk(c, path + '/' + n.type, out)
}
const out = []
walk(j, '', out)
// 找 ⋮ / more_vert / menu 相关
const kws = process.argv[2] || 'more_vert'
const hits = []
function search(n) {
  const s = JSON.stringify(n)
  if (s.includes(kws)) {
    const a = n.attributes || {}
    hits.push({ type: n.type, id: a['id'], text: a['text'], rect: a['rect'] })
  }
  for (const c of (n.children || [])) search(c)
}
search(j)
console.log('hits for', kws, ':', JSON.stringify(hits.slice(0, 8), null, 1))
