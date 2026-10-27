const fs = require('fs')
// 1. CredentialStore: Tag.SECRET union cast
let f = 'entry/src/main/ets/service/CredentialStore.ets'
let s = fs.readFileSync(f, 'utf8')
const D = s.includes('\r\n') ? '\r\n' : '\n'
const oldSecret = '      const secretU8 = rows[0].get(asset.Tag.SECRET)'
const newSecret = [
  '      const secretVal = rows[0].get(asset.Tag.SECRET)',
  '      if (!secretVal || typeof secretVal === \'number\' || typeof secretVal === \'boolean\') {',
  '        return null',
  '      }',
  '      const secretU8: Uint8Array = secretVal'
].join(D)
if (!s.includes(oldSecret)) { console.error('MISS secret'); process.exit(1) }
s = s.replace(oldSecret, newSecret)
fs.writeFileSync(f, s, 'utf8')
console.log('ok: CredentialStore secret cast')

// 2. HttpMcpTransport: ConnectionState.headers field + populate on parse
f = 'entry/src/main/ets/service/HttpMcpTransport.ets'
s = fs.readFileSync(f, 'utf8')
const Dh = s.includes('\r\n') ? '\r\n' : '\n'
const oldConn = 'class ConnectionState {' + Dh + '  client: socket.TCPSocketConnection' + Dh + '  buffer: Uint8Array = new Uint8Array(0)'
const newConn = 'class ConnectionState {' + Dh + '  client: socket.TCPSocketConnection' + Dh + '  buffer: Uint8Array = new Uint8Array(0)' + Dh + '  /** P51: raw request header lines (Mcp-Session-Id lookup) */' + Dh + '  headers: string[] = []'
if (!s.includes(oldConn)) { console.error('MISS conn'); process.exit(1) }
s = s.replace(oldConn, newConn)
// find where headers are parsed into a local array; anchor: "headers.push(h)" style or "const headers"
const hs = s.indexOf('headers: string[] = [')
console.log('conn header init at: ' + hs)
// find request-parse site: look for a local variable collecting header lines
const parseIdx = s.indexOf("'\\r\\n'")
// locate the line where individual header lines are accumulated: search "split('\\r\\n')"
const splitIdx = s.indexOf('split')
console.log('first split idx: ' + splitIdx)
fs.writeFileSync(f, s, 'utf8')
console.log('ok: ConnectionState.headers field added')
