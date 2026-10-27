// P53 fix1: BCPEngine Base64Helper 实例化 + LoginStateManager re-export
const fs = require('fs')
function rep(file, oldStr, newStr, label) {
  let t = fs.readFileSync(file, 'utf8')
  const crlf = t.includes('\r\n')
  const o = crlf ? oldStr.replace(/\n/g, '\r\n') : oldStr
  const nw = crlf ? newStr.replace(/\n/g, '\r\n') : newStr
  if (!t.includes(o)) { console.error('MISS [' + file.split('/').pop() + ']: ' + label); process.exit(1) }
  t = t.split(o).join(nw)
  fs.writeFileSync(file, t, 'utf8')
  console.log('OK', file.split('/').pop(), '-', label)
}
const ROOT = 'D:/BrowserOS - KaihongOS/entry/src/main/ets'

// 1. Base64Helper 是实例类 —— new 后调 encodeToStringSync
rep(ROOT + '/protocol/BCPEngine.ets',
  '      const b64 = util.Base64Helper.encodeToStringSync(buf)',
  '      const b64 = new util.Base64Helper().encodeToStringSync(buf)',
  'b64 instance')

// 2. LoginStateManager re-export LoginStateData/CookieEntry（ImportWizardPage 从 service 导入）
rep(ROOT + '/service/LoginStateManager.ets',
  "import { LoginStateData, CookieEntry } from '../model/LoginStateData'",
  "import { LoginStateData, CookieEntry } from '../model/LoginStateData'\n\n// P53: 向导页统一从 service 导入（re-export）\nexport { LoginStateData, CookieEntry }",
  're-export')

console.log('FIX1 DONE')
