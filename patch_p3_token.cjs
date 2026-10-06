// P3 装机棒: token 外显补丁
// 1) StorageManager.getBasePath() — 暴露基路径
// 2) MCPServer.start() 成功后写 files/mcp_token.txt + console.info 留痕
const fs = require('fs');
const path = require('path');
const root = 'D:/BrowserOS - KaihongOS/entry/src/main/ets';

function patch(rel, anchor, insert, tag) {
  const p = path.join(root, rel);
  let s = fs.readFileSync(p, 'utf8');
  // 归一锚点匹配（文件为混合行尾，统一按 \n 匹配再写回）
  const norm = s.replace(/\r\n/g, '\n');
  if (!norm.includes(anchor)) { console.error('[' + tag + '] ANCHOR NOT FOUND: ' + anchor.slice(0, 60)); process.exit(1); }
  if (norm.includes(insert.trim().split('\n')[0]) && insert.trim().length > 0 && norm.includes(insert.trim())) {
    console.log('[' + tag + '] already patched, skip');
    return;
  }
  const patched = norm.replace(anchor, anchor + '\n' + insert);
  // 写回保持 CRLF（与工程现有风格一致）
  fs.writeFileSync(p, patched.replace(/\n/g, '\r\n'));
  console.log('[' + tag + '] OK');
}

// ---- 1. StorageManager.getBasePath ----
patch('storage/StorageManager.ets',
  `  setBasePath(path: string): void {
    this.basePath = path
  }`,
  `
  /** P3: 暴露基路径（token 外显等沙盒文件绝对路径留痕用） */
  getBasePath(): string {
    return this.basePath
  }`,
  'getBasePath');

// ---- 2. MCPServer.start() 写 token 文件 ----
// import 区补 StorageManager
patch('service/MCPServer.ets',
  `import { HttpMcpTransport, McpHttpDelegate } from './HttpMcpTransport'`,
  `import { HttpMcpTransport, McpHttpDelegate } from './HttpMcpTransport'
import { StorageManager } from '../storage/StorageManager'`,
  'mcp-import');

// start() 成功尾部写文件留痕
patch('service/MCPServer.ets',
  `    console.info('[MCPServer] started, HTTP transport listening on 0.0.0.0:' + this.port)
    return true`,
  `
    // P3: token 外显 —— 写入应用沙盒 files/mcp_token.txt（宿主经 hdc cat 可读）
    const tokenFile = StorageManager.getBasePath() + '/mcp_token.txt'
    const saved = await StorageManager.save('mcp_token.txt', this.authToken)
    if (saved) {
      console.info('[MCPServer] authToken persisted to ' + tokenFile)
    } else {
      console.error('[MCPServer] authToken persist FAILED to ' + tokenFile)
    }
    return true`,
  'mcp-persist');

console.log('ALL PATCHES DONE');
