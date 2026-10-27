const fs = require('fs')
const f = 'entry/src/main/ets/service/CredentialStore.ets'
let s = fs.readFileSync(f, 'utf8')
const D = s.includes('\r\n') ? '\r\n' : '\n'
function rep(o, n, tag) {
  const oo = o.split('\n').join(D), nn = n.split('\n').join(D)
  if (!s.includes(oo)) { console.error('MISS: ' + tag); process.exit(1) }
  s = s.replace(oo, nn)
  console.log('ok: ' + tag)
}
const oldMeta = "        const meta: object[] = []\n        for (const c of all) {\n          meta.push({\n            id: c.id,\n            domain: c.domain,\n            username: c.username,\n            password: '',\n            createdAt: c.createdAt\n          } as object)\n        }"
const newMeta = "        const meta: Credential[] = []\n        for (const c of all) {\n          const m: Credential = {\n            id: c.id,\n            domain: c.domain,\n            username: c.username,\n            password: '',\n            createdAt: c.createdAt\n          }\n          meta.push(m)\n        }"
const oldMeta2 = "      const meta: object[] = []\n      for (const c of arr) {\n        meta.push({\n          id: c.id,\n          domain: c.domain,\n          username: c.username,\n          password: '',\n          createdAt: c.createdAt\n        } as object)\n      }"
const newMeta2 = "      const meta: Credential[] = []\n      for (const c of arr) {\n        const m: Credential = {\n          id: c.id,\n          domain: c.domain,\n          username: c.username,\n          password: '',\n          createdAt: c.createdAt\n        }\n        meta.push(m)\n      }"
rep(oldMeta, newMeta, 'persist-meta')
rep(oldMeta2, newMeta2, 'migrate-meta')
fs.writeFileSync(f, s, 'utf8')
console.log('done')
