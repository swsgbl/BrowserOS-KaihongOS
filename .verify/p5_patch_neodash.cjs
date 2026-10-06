const fs = require('fs');
const path = 'entry/src/main/ets/pages/NeoDashboardPage.ets';
let src = fs.readFileSync(path, 'utf8').replace(/\r\n/g, '\n');

// ---- 5: dark theme color remap (BrowserOS neo style) ----
// 页面底 #FFFFFF -> #0D1117（两处：build 根 Column、卡片内 #FFFFFF）
// 卡片/面板 #F8F8F8 -> #161B22；入口条 #F0F7FF -> #161B22
// 文字 #333333 -> #E6EDF3；#666666 -> #8B949E；#999999 -> #8B949E
// 主按钮 #007DFF -> #1F6FEB；回放 #FF9800 -> #9E6A03；停止 #F44336 保留
const map = [
  ["backgroundColor('#F0F7FF')", "backgroundColor('#161B22')"],
  ["backgroundColor('#F8F8F8')", "backgroundColor('#161B22')"],
  ["backgroundColor('#FFFFFF')", "backgroundColor('#0D1117')"],
  ["fontColor('#333333')", "fontColor('#E6EDF3')"],
  ["fontColor('#666666')", "fontColor('#8B949E')"],
  ["fontColor('#999999')", "fontColor('#8B949E')"],
  ["backgroundColor('#007DFF')", "backgroundColor('#1F6FEB')"],
  ["backgroundColor('#FF9800')", "backgroundColor('#9E6A03')"],
  ["backgroundColor('#4CAF50')", "backgroundColor('#238636')"],
  ["fontColor('#4CAF50')", "fontColor('#3FB950')"],
  ["fontColor('#F44336')", "fontColor('#F85149')"],
];
let counts = [];
for (const [oldS, newS] of map) {
  const n = src.split(oldS).length - 1;
  if (n > 0) {
    src = src.split(oldS).join(newS);
    counts.push(oldS + ' x' + n);
  }
}
fs.writeFileSync(path, src.replace(/\n/g, '\r\n'), 'utf8');
console.log('NeoDashboard dark theme applied: ' + counts.join(', '));
