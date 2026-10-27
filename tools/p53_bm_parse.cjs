const t = require('fs').readFileSync('D:/BrowserOS - KaihongOS/evidence/p53/bm_dump.txt', 'utf8')
const re = /"(dataDir|codePath|dataBaseDir|cacheDir|filesDir|appDistributionType|appProvisionType|bundleName)"\s*:\s*"[^"]*"/g
let m, out = []
while ((m = re.exec(t)) !== null) out.push(m[0])
console.log(out.join('\n'))
