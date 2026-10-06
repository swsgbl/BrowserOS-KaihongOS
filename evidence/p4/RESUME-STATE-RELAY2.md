# P4 relay2 断点（2026-10-06 12:45 收敛退场，Zodex 监督）

## 状态：代码全部落地装机 + 两缺陷实测通过；遗留 screenshots=0 与回放 UI 走查，转 Zodex

## 已完成（勿重做）
1. 缺陷1 GET /mcp：真根因是**空 body decodeUtf8 → undefined → bodyText.length 抛 TypeError 被吞**（relay1 的 findHeaderEnd 假设不成立）。修复在 HttpMcpTransport.ets：空缓冲 break / (loose||contentLength===0) 时 bodyText='' / dispatch 加 .catch / loose GET 兜底 + tailHex 诊断。实测 405 ✓
2. 缺陷2 getText：Types.ets + HttpMcpTransport 两处统一 'getText'。tools/list 实测含 getText、get_text 绝迹；agent 任务里真实调用 ✓
3. P4 五文件：SessionManager（tabId/startRecording/captureRecordingData/createReplayerAsync）、AgentEngine（agentSessions/addOperationLog/addUrlChange/stopRecording/getSessionId）、SessionPlayerPage（router 参数+async）、NeoDashboardPage（回放按钮）、Constants（medium 3000 实测 3s 间隔 ✓）
4. v11c 装机链全通：build → python .verify/p4_repack.py（降 API14）→ file send → VM hap-sign-tool（browseros-profile-release.p7b）→ bm install -r → force-stop + start。**铁则：改码后必须先 build 再 repack**（曾漏，装了旧码）
5. 会话 JSON 落盘实证：sessions/ses_1791260949697（10 条 operationLogs）、ses_1791261403052（6 条）

## 遗留（Zodex 接手）
- screenshots=0：agent 运行时停在 NeoDashboardPage，WebView 销毁。复现要点：**创建 agent 后立即点←返回 BrowserShell 并新建标签页**（WebView 存活），3s capture 即入 screenshots。urlSequence 同因。
- 回放按钮端到端：跑 agent 至 COMPLETED → NeoDashboard 代理卡片点"回放" → SessionPlayerPage 应显示截图/日志。
- uiInput inputText 中文未验。

## 关键路径/命令（勿再摸索）
- token: /data/app/el2/100/base/com.browseros.kaihong/haps/entry/files/mcp_token.txt（不是 /data/storage/！）
- sessions: 同目录 files/sessions/*.json
- fport 9222 已在；原始 GET 探针脚本 .verify/p4_raw_get.cjs；MCP 测试 .verify/p4_mcp_test.cjs
- hilog 取证：先 hilog -x > /data/local/tmp/x.txt 再设备端 grep（cmd 宿主无管道，用 node 脚本 .verify/p4_grep*.cjs 范式）
- UI 坐标（1600x900）：Dashboard 标签 (800,87) / 查看代理 (800,214) / 名称框 (800,204) / URL 框 (800,241) / 任务框 (800,279) / 创建代理 (800,320) / 新建标签页 (712,213) / 返回 (46,54)
- 补丁脚本：.verify/p4_patch.cjs + p4_patch2.cjs（CRLF 感知，锚点唯一断言）；文件全 CRLF 无 BOM，edit_file 多行匹配会失败，一律走 node 补丁
