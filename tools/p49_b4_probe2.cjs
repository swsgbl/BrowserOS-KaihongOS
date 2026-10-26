// B4 深挖2：JSON-RPC 规范格式（method tools/call 应该在 params.name）——上面用的就是这个。
// "not found" 说明路由层拒绝了。对比 python 版（能通）的差异：python 是 /mcp?token=xxx + 同样 body。
// 检查：是不是 fport 隧道断了？或 app 重启后 token 轮换（tail sLss 同旧）？
// 直接 python 复刻一次调用
const { execSync } = require('child_process')
const out = execSync('python -c "import urllib.request,json;req=urllib.request.Request(\'http://127.0.0.1:19222/mcp?token=' + process.env.TOKEN + '\',data=json.dumps({\'jsonrpc\':\'2.0\',\'id\':1,\'method\':\'tools/list\',\'params\':{}}).encode(),headers={\'Content-Type\':\'application/json\'});print(urllib.request.urlopen(req,timeout=10).read().decode()[:200])"', { encoding: 'utf8', env: { ...process.env, TOKEN: execSync('\"C:\\Program Files\\Huawei\\DevEco Studio\\sdk\\default\\openharmony\\toolchains\\hdc.exe\" -t 192.168.161.137:10178 shell cat /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt', { encoding: 'utf8' }).trim().split(/\r?\n/).pop() } })
console.log(out)
