const fs = require('fs')
let py = fs.readFileSync('tools/session_isolation_test.py', 'utf8')
const mainNew = fs.readFileSync('tools/p51_e2e_main.txt', 'utf8')
const i = py.indexOf('def main():')
const summaryAnchor = "    print('\\n==== SUMMARY ====')"
const j = py.indexOf(summaryAnchor)
if (i < 0 || j < 0 || j < i) { console.error('anchors', i, j); process.exit(1) }
py = py.substring(0, i) + mainNew + py.substring(j)
fs.writeFileSync('tools/session_isolation_test.py', py, 'utf8')
console.log('main() replaced; new size', py.length)
