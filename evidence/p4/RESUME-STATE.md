# P4 断点接力（P4 录制回放 + P3 两缺陷）RESUME-STATE — relay1 勘察完成

日期: 2026-10-06 ｜ 本棒完成: 全部源码勘察 + 两缺陷根因定位，未动代码。下棒直接改码勿重读大文件。

## 环境/流水线事实（已验证）
- VM 在线: hdc target 127.0.0.1:15566，fport 9222→9222 隧道已建（hdc fport ls 实证）
- hdc: `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`
- 宿主 cmd 无 grep：hilog 过滤用 `hdc shell hilog -x > file.txt` 再宿主 `findstr /i "xxx" file.txt`
- 装机流水线: DEVPLAN「已验证装机流水线」节（v10 签名 browseros-profile-release.p7b，VM 内 hap-sign-tool，bm install -r，aa start -b com.browseros.kaihong）
- 构建命令: `cd /d "D:\BrowserOS - KaihongOS" && hvigorw assembleHap --mode module -p product=default -p buildMode=debug`
- 红线: 不碰 D:\oneaiterm、不重启 VM、不卸载任何包、API≤14、ArkTS 严格模式、无新依赖、无新权限

## 缺陷1: GET /mcp 挂起 — 根因已锁定到唯一分叉点
hilog 铁证（evidence/p4/ 相关日志已在 p4_hilog_raw.txt）:
- GET 请求 onBytes 到达正常: 如 `onBytes id=1 len=80 head=47 45 54 20 2f 6d 63 70 20 48 54 54 50 2f 31 2e 31 0d 0a 48 6f 73 74 3a`（"GET /mcp HTTP/1.1\r\nHost:"）+ id=15 len=292 / id=20 len=292 / id=9 len=297（带 token 的 GET）
- **但 dispatch 首行日志 `[MCP-HTTP] GET /mcp client=...` 从未出现**；POST 全部正常 dispatch
- 客户端 5s 超时断开（11:00:34.368 onBytes → 11:00:39.368 client closed）
分叉点: HttpMcpTransport.ets onBytes 分帧循环中 `findHeaderEnd(buf)` 返回 -1 → break 等更多数据（唯一无声吞请求路径）。即 GET 请求字节流里找不到 `\r\n\r\n`（嫌疑: undici/fetch 的 GET 经 fport 转发尾部终结符被拆包未达，或该 GET 确实无标准终结）。
修法（双保险，文件 entry/src/main/ets/service/HttpMcpTransport.ets）:
1. findHeaderEnd 返回 -1 的 break 前加诊断日志（tailHex 后 16 字节），装机复现拿真凶证据
2. 宽松兜底: 找不到 \r\n\r\n 时，若①请求行完整（含首个 \r\n）②method 为 GET（无 body 语义）③无 Content-Length 或为 0 ④缓冲区以 `\n`(0x0a) 结尾 → 视 header 结束（headerEnd=buf.length-1，total=buf.length），直接 dispatch
3. dispatch 的 GET 405 分支代码本身完好无需改

## 缺陷2: tools/call(getText) 报工具不存在 — 根因: 命名不一致
- entry/src/main/ets/common/Types.ets:30 `GET_TEXT = 'get_text'`（snake_case，其余 9 工具全是单词小写: navigate/click/type/screenshot/snapshot/scroll/wait/back/forward）
- MCPServer.ets registerToolHandlers 用 ToolType.GET_TEXT 做注册表 key → 实际注册名 `get_text`
- AgentEngine.getToolSpecs/executeToolCall 用 `getText`（LLM 侧也叫 getText）
- HttpMcpTransport.ets buildToolDescriptors 里也写死 `this.toolDef('get_text', ...)`
修法: ①Types.ets GET_TEXT 改 `'getText'` ②HttpMcpTransport buildToolDescriptors `'get_text'`→`'getText'` ③全库 findstr "get_text" 清余党（检查 pages/TestPage 等）。改完全链对齐: LLM(getText) = AgentEngine(getText) = MCP 注册表(getText) = tools/list 描述符(getText)，10 工具全可调

## P4 实施（全部坐标已勘明）
### 1. SessionManager.ets（entry/src/main/ets/service/）
- captureRecordingData(sessionId, agentId) 当前是空壳（只 checkStorageSpace）——真实现:
  - `import { ScreenshotCapture } from '../protocol/ScreenshotCapture'` + `import { TabManager } from './TabManager'`
  - 取 URL: 需 agentId→tabId。方案: startRecording(agentId) 增加第 2 参 tabId: string（可选默认 ''），存 `sessionTabs: Map<string,string>`（sessionId→tabId）；capture 时 `TabManager.getTab(tabId)?.currentUrl`
  - 截图: `const r = await ScreenshotCapture.capture(quality)`; r.success && r.data → `session.addScreenshot(new ScreenshotEntry(r.data, url))`（ScreenshotEntry 构造 (base64Data, url)，ScreenshotCapture 已保证 data:image/jpeg;base64, 前缀）
  - URL 变化: url 非空且 ≠ urlSequence 最后一条 → session.addUrl(url)
  - 必打日志: `console.info('[SessionManager] capture shot#' + (session.screenshots.length) + ' url=' + url + ' size=' + r.data.length)`（hilog 验收依赖）
  - startRecording 也加日志 `[SessionManager] startRecording session=xxx agent=xxx`
- Constants.ets RECORDING_INTERVAL_MAP: medium 2000→3000（默认 quality=medium，任务要求 3s）
- stopRecording 已调 persistSession ✓ 无需改。persistSession 落 `sessions/<id>.json`（StorageManager base=filesDir，即设备 /data/app/.../files/sessions/）
- createReplayer(sessionId) 只查 activeSessions——回放已结束会话需改: 先 getSessionDetail(sessionId)（async），有则 new SessionReplayer(session)。改签名 async 或新增 createReplayerAsync；SessionPlayerPage.loadSession 调用点同步改
### 2. AgentEngine.ets
- import: `import { SessionManager } from './SessionManager'` + `import { OperationLog } from '../model/SessionRecord'`
- 新增 `private agentSessions: Map<string,string> = new Map()`（agentId→sessionId）
- runAgentTask: LLM 配置检查通过后（setAgentRunning 附近）: `const session = SessionManager.startRecording(agentId, config.tabId); if (session) this.agentSessions.set(agentId, session.sessionId)`
- 每次 executeToolCall 后: `const sid = this.agentSessions.get(agentId); if (sid) SessionManager.addOperationLog(sid, new OperationLog(call.function_name, args摘要(≤60字), result.success ? 'success' : 'fail', result摘要(≤100字)))`；navigate 成功后另 `SessionManager.addUrlChange(sid, url)`
- 任务结束（failed/completed 两分支 + finally）: `const sid = this.agentSessions.get(agentId); if (sid) { SessionManager.stopRecording(sid); this.agentSessions.delete(agentId) }`——注意在 setAgentError/setAgentCompleted 之后调
- 新增公共方法 `getSessionId(agentId): string`（NeoDashboardPage 回放入口用）
### 3. SessionPlayerPage.ets
- `import { router } from '@kit.ArkUI'`
- aboutToAppear: `const p = router.getParams() as Record<string, Object>; if (p && p['sessionId']) this.sessionId = p['sessionId'] as string` 然后原有 loadSession
- loadSession 改用新 createReplayerAsync；加载后打日志 `console.info('[SessionPlayer] loaded session=' + this.sessionId + ' shots=' + (session ? session.screenshots.length : 0) + ' logs=' + (session ? session.operationLogs.length : 0))`（hilog 验收依赖）
- Image(this.currentScreenshot) 已支持 data URL ✓；无截图显示「无截图数据」兜底 ✓
### 4. NeoDashboardPage.ets
- 代理卡片（AgentList ForEach 内，status.status 为 COMPLETED 或 ERROR 时）加「回放」Button:
  `onClick: router.pushUrl({ url: 'pages/SessionPlayerPage', params: { sessionId: AgentEngine.getSessionId(status.agentId) } })`（router 已 import）
### 5. 路由确认: main_pages.json 已含 SessionPlayerPage（P1 骨架注册过，构建前 findstr 验证一下）

## 验收路径（任务6）
1. 装机后 MCP 通道复测: 宿主 `curl http://127.0.0.1:9222/mcp -X GET`（应 405 立即返回）+ tools/list 应含 getText + tools/call getText 应穿透 BCP 层
2. 创建 agent 跑任务: hilog grep 链路: startRecording → capture shot#N → addOperationLog（tool 名）→ stopRecording
3. `hdc shell ls /data/app/el2/100/base/com.browseros.kaihong/files/sessions/` 有 JSON；`hdc shell cat` 含 screenshots 数组
4. UI 回放页: 若前台被 oneaiterm 抢占，hilog 证明 `[SessionPlayer] loaded session=... shots=N` 即可（pushUrl 经 MCP navigate 或 UI；UI 不可得则如实记录）
5. DEVPLAN 追加 P4 汇报

## 已知坑（历史教训）
- cmd 文件 GBK: 本项目 .ets 全 UTF-8，edit_file 可用；deploy 脚本勿乱动
- hdc file recv 要反斜杠路径
- build 失败先 harmony_build_doctor；warn 12 条（WebViewAdapter may-throw 8 + decodeWithStream deprecated 4）是存量勿修
- 每步写操作后闭环验证（写配置回读、commit 后 git log）
