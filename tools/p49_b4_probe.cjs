// B4 深挖：navigate example.com → snapshot → read 全文
const http = require('http')
const { execSync } = require('child_process')
const HDC = '"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe"'
const token = execSync(HDC + ' -t 192.168.161.137:10178 shell cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt', { encoding: 'utf8' }).trim().split(/\r?\n/).pop()
console.log('token tail:', token.slice(-4))
const post = (body) => new Promise((res, rej) => {
  const r = http.request({ host: '127.0.0.1', port: 19222, path: '/mcp?token=' + token, method: 'POST', headers: { 'Content-Type': 'application/json' } }, resp => {
    let d = ''; resp.on('data', c => d += c); resp.on('end', () => { try { res(JSON.parse(d)) } catch (e) { res({ raw: d }) } })
  })
  r.on('error', rej)
  r.write(JSON.stringify(body)); r.end()
})
const sleep = (ms) => new Promise(s => setTimeout(s, ms))
;(async () => {
  let r = await post({ jsonrpc: '2.0', id: 201, method: 'tools/call', params: { name: 'navigate', arguments: { url: 'https://example.com' } } })
  console.log('navigate:', JSON.stringify(r).slice(0, 400))
  await sleep(7000)
  r = await post({ jsonrpc: '2.0', id: 202, method: 'tools/call', params: { name: 'snapshot', arguments: {} } })
  console.log('snapshot:', JSON.stringify(r).slice(0, 700))
  r = await post({ jsonrpc: '2.0', id: 203, method: 'tools/call', params: { name: 'read', arguments: {} } })
  console.log('read:', JSON.stringify(r).slice(0, 500))
})().catch(e => console.error('ERR', e.message))
