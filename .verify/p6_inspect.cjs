const fs = require('fs');
const f = 'entry/src/main/ets/components/NeoDashboardPanel.ets';
let c = fs.readFileSync(f, 'utf8');
// 打印 代理名称 附近原文（JSON 转义以便看清）
const i = c.indexOf('placeholder');
console.log(JSON.stringify(c.substring(i - 20, i + 260)));
const j = c.indexOf('llmModelInput2');
console.log(JSON.stringify(c.substring(j - 200, j + 120)));
