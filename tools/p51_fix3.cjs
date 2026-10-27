const fs = require('fs')
const D = '\r\n'

// ---- CredentialStore fixes ----
let f = 'entry/src/main/ets/service/CredentialStore.ets'
let s = fs.readFileSync(f, 'utf8')
function rep2(o, n, tag) {
  const oo = o.split('\n').join(D), nn = n.split('\n').join(D)
  if (!s.includes(oo)) { console.error('MISS: ' + tag); process.exit(1) }
  s = s.replace(oo, nn, )
  console.log('ok: ' + tag)
}
// 1+2. replace both untyped meta literals with Credential-typed shallow copies (copy via constructor-free clone)
const oldMeta = "        const meta: object[] = []\n        for (const c of all) {\n          meta.push({\n            id: c.id,\n            domain: c.domain,\n            username: c.username,\n            password: '',\n            createdAt: c.createdAt\n          } as object)\n        }"
const newMeta = "        const meta: Credential[] = []\n        for (const c of all) {\n          const m = new Credential(c.id, c.domain, c.username, '')\n          m.createdAt = c.createdAt\n          meta.push(m)\n        }"
const oldMeta2 = "      const meta: object[] = []\n      for (const c of arr) {\n        meta.push({\n          id: c.id,\n          domain: c.domain,\n          username: c.username,\n          password: '',\n          createdAt: c.createdAt\n        } as object)\n      }"
const newMeta2 = "      const meta: Credential[] = []\n      for (const c of arr) {\n        const m = new Credential(c.id, c.domain, c.username, '')\n        m.createdAt = c.createdAt\n        meta.push(m)\n      }"
rep2(oldMeta, newMeta, 'persist-meta')
rep2(oldMeta2, newMeta2, 'migrate-meta')
// 3. Tag.SECRET union type -> Uint8Array cast
rep2('      const secretU8 = rows[0].get(asset.Tag.SECRET)',
     '      const secretVal = rows[0].get(asset.Tag.SECRET)\n      if (!secretVal || typeof secretVal === 'number' || typeof secretVal === 'boolean') {\n        return null\n      }\n      const secretU8: Uint8Array = secretVal')
fs.writeFileSync(f, s, 'utf8')

// ---- HttpMcpTransport: ConnectionState.headers ----
f = 'entry/src/main/ets/service/HttpMcpTransport.ets'
s = fs.readFileSync(f, 'utf8')
const Dh = s.includes('\r\n') ? '\r\n' : '\n'
const oldConn = 'class ConnectionState {\n  client: socket.TCPSocketConnection\n  buffer: Uint8Array = new Uint8Array(0)'
const newConn = 'class ConnectionState {\n  client: socket.TCPSocketConnection\n  buffer: Uint8Array = new Uint8Array(0)\n  /** P51: raw request header lines (for Mcp-Session-Id lookup) */\n  headers: string[] = []'
if (!s.includes(oldConn.split('\n').join(Dh))) { console.error('MISS: ConnectionState'); process.exit(1) }
s = s.replace(oldConn.split('\n').join(Dh), newConn.split('\n').join(Dh))
console.log('ok: ConnectionState.headers')
// populate conn.headers when headers parsed — find where headers.join is used
const idx = s.indexOf("headers.join('")
console.log('headers.join idx: ' + idx)
fs.writeFileSync(f, s, 'utf8')
console.log('all fixed')
