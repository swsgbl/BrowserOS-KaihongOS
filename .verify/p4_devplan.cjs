const fs = require('fs');
const p = 'D:\\BrowserOS - KaihongOS\\DEVPLAN.md';
let t = fs.readFileSync(p, 'utf8');
const report = `

## P4 汇报（2026-10-06 12:4x，relay2 执行，Zodex 监督收敛）

### 缺陷修复（两项全通过，实测取证）
1. **GET /mcp 挂起 → 405**：HttpMcpTransport.ets 分帧修复。
   - relay1 假设（findHeaderEnd 找不到 CRLFCRLF）**不成立**——实测 72B 标准 GET 的 CRLFCRLF 能找到、buf 被正常消费，但 dispatch 内部抛异常被吞。
   - 真根因：GET 无 body，decodeUtf8(subarray(n,n)) 对空 Uint8Array 在该 netstack 返回 undefined，bodyText.length 抛 TypeError，async rejection 被 ArkTS 吞掉 → 客户端永久挂起。
   - 修复三件套：空缓冲提前 break（消噪）；(loose || contentLength===0) 时空 body 直接 ''；dispatch(...) 加 .catch 打日志。
   - 另保留宽松 GET 分帧兜底（loose framing）+ findFirstLineEnd 辅助 + header 未找到时 tail=16字节hex 诊断日志。
   - 实测：原始 TCP 探针 GET /mcp?token=abc（72B）→ 立即收到 \`HTTP/1.1 405 Method Not Allowed ... {"error":"POST only"}\`（修复前同探针 5s 窗口 0 字节）。
2. **getText 命名统一**：Types.ets GET_TEXT 'get_text'→'getText'；HttpMcpTransport buildToolDescriptors 同步。全库 findstr 清余党（仅 BCP 内部 JS 函数 __bcp_get_text 保留不动）。
   - 实测：tools/list → navigate,click,type,screenshot,snapshot,scroll,getText,wait,back,forward（get_text 绝迹）；tools/call getText → 200 正常应答（WebView 未绑定时返回业务错误 JSON，链路本身通）；真实 agent 任务 operationLogs 中记录 getText 调用。

### P4 录制回放管道（代码全部落地并装机）
- SessionManager：startRecording(agentId, tabId) 加 tabId 参数 + sessionTabs Map；captureRecordingData 真实现（TabManager.getTab 取 URL + ScreenshotCapture.capture 截图 + addUrl 去重）；stopRecording 清 sessionTabs；新增 createReplayerAsync（异步查 getSessionDetail）。全部打 [SessionManager] 日志。
- Constants：RECORDING_INTERVAL_MAP medium 2000→3000（实测 12:30:30→33→36→39→42 间隔恰 3s ✓）。
- AgentEngine：import SessionManager/OperationLog；agentSessions Map；runAgentTask 起 recording（带 config.tabId）、每次 tool_result 后 addOperationLog（args 截 60/结果截 100 预览）、navigate 成功时 addUrlChange、任务收尾 stopRecording；新增 getSessionId(agentId)。
- SessionPlayerPage：aboutToAppear 接 router.getParams()['sessionId']；loadSession 改用 await createReplayerAsync + 落盘日志。
- NeoDashboardPage：代理卡片 COMPLETED/ERROR 状态显示"回放"按钮 → router.pushUrl SessionPlayerPage(带 sessionId)。
- 装机链：hvigorw assembleHap → repack（python .verify/p4_repack.py 降 API14）→ hdc file send → VM 端 hap-sign-tool（browseros-profile-release.p7b）→ bm install -r → force-stop 重启。**注意每次改码后必须先构建再 repack**（曾漏构建直接 repack 导致装机旧码）。

### 实测证据（通过项）
- MCP token 真实路径：/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt（注意不是 /data/storage/...）
- 会话落盘：/data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/sessions/ses_*.json
  - ses_1791260949697（P4Relay2 agent）：operationLogs=10 条完整（navigate/wait/getText/snapshot，含 operationType/targetElement/timestamp/result/detail）
  - ses_1791261403052（P4Shot agent）：operationLogs=6 条
- 录制定时器、任务接线、日志全部工作正常（hilog 实证）。

### 遗留项（如实记录，转 Zodex）
- **screenshots=0**：agent 运行期间停留在 NeoDashboardPage（BrowserShell WebView 销毁），capture 返回"JS Bridge注入失败：WebView未准备好"。复现要点：创建 agent 后立即返回 BrowserShell 并新建标签页（WebView 存活），capture 即可入 screenshots。代码路径本身已验证（失败分支有日志、成功分支代码同构）。urlSequence 同因（tab.currentUrl 依赖 tab 存在）。
- 回放按钮/SessionPlayerPage 端到端 UI 走查未做（需人工或下棒：跑一个 agent 至 COMPLETED 后点"回放"）。
- uiInput inputText 对中文输入未验证（本次全英文）。
`;
fs.appendFileSync(p, report, 'utf8');
console.log('DEVPLAN appended, new length=' + (t.length + report.length));
