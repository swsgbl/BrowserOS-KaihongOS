# BrowserOS KaihongOS 开发计划（权威路线图）

> 本文件是 Zodex（指挥/审核）与 hmharness（开发）的共享上下文。每个开发任务以此为准。
> 上游对标：https://github.com/browseros-ai/BrowserOS（BrowserOS neo：给 AI Agent 用的浏览器）
> 官网七卖点：Live Dashboard / One-Click Connect / Replay / Import Logins / Parallel Agents / Fewer Tokens / Local-First Privacy

## 工程约定

- 工程路径：`D:\BrowserOS - KaihongOS`
- **bundleName 变更指令（2026-10-06 用户下令，替代旧约束"不改 bundleName"）**：旧名 `com.oneaiterm.terminal` 与 oneAIterm 项目（D:\oneaiterm）撞包、互相覆盖装机。改为独立包名（建议 `com.browseros.kaihong`），与 oneAIterm 同机共存。红线：不碰 D:\oneaiterm、不重启 VM/QEMU、不卸载 com.oneaiterm.terminal（对方项目自行回收）、不碰 hdc 127.0.0.1:5555。全库搜索旧包名字符串（AppScope/module json5、装机脚本、DEVPLAN 流水线命令、文档）一并更新。若签名 profile（app1-profile-release.p7b）内嵌 bundle-name 则需改 profile 源 JSON 后用 hap-sign-tool 重新生成 p7b（装机报 9568325 即包名签名不匹配）。验收 A1-A4：bm dump -a 双包共存 / 新包 aa start 进 BrowserShell / 连装两次新包不影响旧包 / 后续装机不再互相覆盖。
- SDK：compatible/target 26.0.0（KaihongOS 5.0 / HarmonyOS）
- hdc：`"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"`
- 装机目标：Quickemu KaihongOS 5.0 虚拟机（**OpenHarmony API 14 镜像**），hdc target `127.0.0.1:15566`（若断线先确认 VM 在跑）
- **API 约束**：设备只到 API 14！所有设备上要跑的代码必须 ≤API 14 可用（写码前 `harmony_api_lookup` 查版本注解）。Web 组件/runJavaScript/@ohos.net.http/TCPSocketServer/webSocket 均在 ≤API 14 可用，但需逐符号核对
- **已验证装机流水线**（deploy_hap.py，实测可用，hmh 每次装机照此执行）：
  1. `hvigorw assembleHap --mode module -p product=default -p buildMode=debug` 产出 `entry/build/default/outputs/default/entry-default-unsigned.hap`
  2. 解包 HAP → 改 module.json（minAPIVersion/targetAPIVersion=14, compileSdkVersion='14', compileSdkType='OpenHarmony'）+ pack.info（compatible/target=14）→ 重打包 zip
  3. `hdc file send <hap> /data/local/tmp/entry-api14.hap`
  4. **VM 内签名**：`hdc shell '/data/local/home/.local/bin/hap-sign-tool sign-app -keyAlias "OpenHarmony Application Release" -signAlg SHA256withECDSA -mode localSign -appCertFile /data/local/home/.ohos/signature/OpenHarmonyApplication.pem -profileFile /data/local/home/.ohos/signature/app1-profile-release.p7b -inFile /data/local/tmp/entry-api14.hap -outFile /data/local/tmp/entry-api14-signed.hap -keystoreFile /data/local/home/.ohos/signature/OpenHarmony.p12 -keyPwd 123456 -keystorePwd 123456 -compatibleVersion 14'`
  5. `hdc shell bm install -p /data/local/tmp/entry-api14-signed.hap -r`
  6. `hdc shell aa start -a EntryAbility -b com.browseros.kaihong`
  7. 验证：`hdc shell snapshot_display -f /data/local/tmp/verify.jpeg` → `hdc file recv` 回看；`hdc shell "hilog -x | grep -i jsapp | tail -20"`
- 每阶段验收流程：构建 → 上述装机流水线 → 交互验证 → 截图留证 → DEVPLAN 勾选
- 写 ArkTS 代码前先用 hmharness `harmony_api_lookup` 查本地 SDK d.ts 真实声明（API 26），禁止凭记忆猜 API
- UI 一比对齐 BrowserOS neo：暗色 dashboard、agent 卡片流、会话回放播放器

## 现状审计结论（2026-10-05，Zodex 全量审计）

架构完整、接线断裂。UI 壳/模型层/存储层/事件总线/错误码完整；docmanagement 模块完整但与本体无关。
**四大核心能力缺失：**
1. 无网页渲染：全项目 0 处 `@ohos.web.webview` / `Web()`，网页区是占位文字"Web组件在当前系统上暂不可用"
2. 无 MCP 网络层：MCPServer.start() 只置 flag，无 socket/JSON-RPC/SSE
3. 无 Agent 执行：AgentEngine 无任务循环，无任何 HTTP 调用（全项目 0 处 `@ohos.net.http`），代理创建后永远 IDLE
4. 录制回放断链：captureRecordingData() 空函数，addScreenshot 无调用方，fromJSON 丢截图数据

**接线断点清单：**
- BrowserShell.webviewController 永远 null；navigate() 只改状态；刷新/查看代理/导入登录态按钮空 onClick
- 5 个页面（Dashboard/NeoDashboard/SessionPlayer/Onboarding/Test）注册了路由但无任何 router 跳转入口，不可达
- ConfirmDialog/AddressBar/TabBar/AgentCard/ConnectionPanel/SessionList 六个组件零引用（孤儿）
- SensitiveOperationDetector.requestConfirmation() 触发后永久挂起（无 UI 消费 SENSITIVE_OPERATION_DETECTED）
- EntryAbility 不初始化 ConfigManager/StorageManager/DocManagement（StorageManager 硬编码 /data/storage 无权限）
- BookmarkManager/HistoryManager.recordNavigation 无 UI 调用方
- 已知 bug：AgentStatus.updateHeartbeat() 先更新 lastHeartbeat 再算 runningDuration → 恒 0；SessionRecord.fromJSON 不还原 operationLogs/screenshots
- SecureStorageAdapter 是 XOR 伪加密 + 硬编码密钥；StorageManager.load() 无 UTF-8 解码（中文乱码）

## 阶段计划

### P1 真实网页渲染内核（最高优先级）⬜
1. 新建 `protocol/WebViewAdapter.ets`：`implements IWebviewController`，内部持 `webview.WebviewController`，透传 runJavaScript/loadUrl/backward/forward/refresh/getTitle
2. BrowserShell 用真 `Web({ controller })` 组件替换占位 WebViewContent；每 Tab 一个 controller（TabManager.registerWebView 接线），激活 Tab 的 Web 组件渲染；JSBridgeInjector 在 onPageEnd 注入
3. 导航闭环：地址栏 onSubmit → webview loadUrl；前进/后退/刷新按钮真调 controller；onPageEnd → HistoryManager.recordNavigation + TabManager 更新 title/url + SensitiveOperationDetector.detectNavigation
4. EntryAbility onCreate 初始化链：StorageManager.setBasePath(context.filesDir) → ConfigManager.load() → DocManagementInitializer.initialize()
5. 修 updateHeartbeat / SessionRecord.fromJSON 两 bug；StorageManager.load() UTF-8 解码
6. 验收：装机后地址栏输入 https://example.com 真实渲染页面；前进后退刷新可用；hilog 无错误

### P2 Agent 大脑（LLM + 执行循环）⬜
1. AppConfig 增加 llmBaseUrl/llmApiKey/llmModel（OpenAI 兼容 /chat/completions），设置 UI（Dashboard 入口）可配并存 ConfigManager
2. AgentEngine 任务执行循环：LLM 请求（@ohos.net.http，system prompt 注入 BCP 工具表）→ 解析 tool_calls → BCPEngine 执行 → snapshot/getText 结果回灌 LLM → 循环直到任务完成或步数上限；每步经 setAgentRunning/updateAgentProgress 推进（激活现有无人调用的状态机）
3. 代理运行时自动绑定其 tabId 的 WebViewAdapter（BCPEngine.bindWebView）
4. NeoDashboardPage 代理卡片实时显示：当前 URL/活动描述/进度（真数据）
5. 验收：配置任一 OpenAI 兼容端点后，创建代理"打开 example.com 并提取标题"能真实执行并返回结果

### P3 MCP 网络层（外部 AI 工具可接入）⬜
1. 基于 `@ohos.net.socket` TCPSocketServer 在 9222 端口实现最小 HTTP/1.1 服务：MCP Streamable HTTP 传输（POST /mcp JSON-RPC 2.0 + 会话管理），支持 initialize/tools/list/tools/call 三个方法映射到现有 MCPServer 10 工具
2. token 鉴权走 query 参数（现有 validateToken 复用）
3. 验收：宿主机用 curl 或 MCP 客户端通过 VM 转发端口完成 initialize+tools/list+tools/call(navigate) 真实返回

### P4 录制回放管道 ⬜
1. captureRecordingData() 真实现：按 Constants.RECORD_INTERVAL 定时调 ScreenshotCapture 截图 + BCP 操作日志采集；AgentEngine 每步自动 addOperationLog/addUrlChange
2. AgentEngine 启动代理时自动 SessionManager.startRecording，完成/出错时 stopRecording
3. SessionPlayerPage 接真 sessionId（从 Dashboard 会话列表 router 跳入），fromJSON 修复后能回放截图序列
4. 验收：跑一个代理任务后，回放页能拖动时间线看到真实页面截图帧

### P5 接线与打磨 ⬜
1. 路由闭环：首启动 Onboarding（isOnboardingCompleted=false 时）→ BrowserShell；Dashboard/SessionPlayer 从地址栏工具按钮进入
2. ConfirmDialog 挂载到 BrowserShell，消费 SENSITIVE_OPERATION_DETECTED，闭环 requestConfirmation
3. 书签按钮 + 书签管理面板（BookmarkManager 接线）；历史记录面板（HistoryManager）
4. UI 对齐 BrowserOS neo 视觉：暗色主题 dashboard、卡片流
5. LoginStateManager：KaihongOS 无 Chrome 数据，改为"从导出的 cookies.json 文件导入 + WebView cookie 配置注入"，UI 文案诚实标注
6. 验收：全功能走查 + 截图对比

## 完成勾选

- [x] P1 真实网页渲染内核（2026-10-05 Zodex 装机验收通过）
- [x] P2 Agent 大脑（2026-10-06 Zodex 终验通过：LLM 循环 12 步协议级全链路；BCP-on-agent-tab 转 P5）
- [ ] P3 MCP 网络层
- [ ] P4 录制回放管道
- [ ] P5 接线与打磨

## 汇报约定

每阶段完成后，hmh 在本文件末尾追加：阶段号、完成项、构建产物路径、装机验证结果（命令+输出摘要）、遗留问题。

---

## 验收记录（Zodex 维护）

### P1 验收（2026-10-05，通过）
- 构建/装机流水线全通；WebViewAdapter + BrowserShell 真 Web 组件 + 导航闭环 + EntryAbility 初始化链 + 3 bug 修复全部落地
- 证据：example.com 真实渲染（Example Domain 页面，截图 p1_verify_web.jpeg / p1_accept_*.jpeg）；hilog：`REFRESH -> controller.refresh()` + onPageBegin/End + JSBridge 重注入；BACK/FORWARD access 检查路径日志；StorageManager base path set + ConfigManager loaded；全程无 BCP_001/JSAPP error
- 测试基建教训：uitest inputText 对地址栏 TextInput 假成功；keyEvent 逐键在"清空后再输入"场景丢焦点（按键被 Web 吃掉）。可靠配方：空字段 → click → keyEvent 2016 → inputText（表单场景）或逐键（地址栏从空开始）

### P2 中期验收记录（2026-10-06，daemon 二次崩溃中断 hmh 收尾，Zodex 复验）
- 已实证：LLMClient（OpenAI 兼容 POST）+ AgentEngine 15 步循环 + 状态机全部落地；「未配置 LLM」错误路径 hilog 铁证（`LLM not configured, agent aborted`）；LLM 设置 UI + ConfigManager 持久化跨重启生效；任务启动链路（`task start → step 1/15 → POST → 失败 → task failed`）错误传播正确
- **待修 bug-1**：持久化 llmBaseUrl 被污染为两段拼接 `http://10.0.2.2:11434/v1http://172.25.0.1:11434/v1`（疑似 hmh 调试期间经 UI 二次保存时 append 而非 replace，或保存逻辑缺陷）——导致 LLM 请求必失败。修复后重验完整循环
- **已知缺口-1**：`WebView not registered for tab tab_2_xxx (agent tools will fail until tab opened)`——后台 agent 的 tab 无 Web 组件挂载（BrowserShell 只渲染激活 tab），并行代理能力要到 P5；当前 agent 的 BCP 工具需其 tab 被激活过才可用。P2 验收路径：创建 agent 后其 tab 激活时工具可用即可

### bundleName 更换验收（2026-10-06，Zodex 独立实证通过）
- 新包名：`com.browseros.kaihong`（app.json5 + deploy_hap.py + deploy_p1.py + 本文件流水线命令共 4 处更新；entry 冗余 app_name 已删）
- 签名链：旧 p7b 装 9568329（包名绑定）→ 宿主 hap-sign-tool sign-profile 重生成 profile（原 JSON 改 bundle-name/uuid/not-after）→ 装机成功。可复用命令固化在 evidence/bundle-rename/RESUME-STATE-RELAY2.md
- **A1** bm dump -a 同时列出 com.browseros.kaihong + com.oneaiterm.terminal（Zodex 复跑实证）✓
- **A2** aa start 新包 → BrowserShell/Dashboard 前台渲染（截图 ren_a2.jpeg + 视觉确认）✓
- **A3** 旧包 bm dump -n 20650 字节完整转储，appIdentifier 在 ✓
- **A4** 全程仅 bm install -r，零 uninstall ✓（红线全程无违：D:\oneaiterm 零写、VM 未重启、5555 未碰）
- bug-1（llmBaseUrl 拼接污染）根因：**设备 TextInput 受控回灌缺陷**（非代码 append，全链审计排除）；已加 sanitize 三点消毒，污染注入实测通过（双拼 URL → 重启 → 显示单一 URL）
- 已知限制：旧包名应用数据不迁移（全新数据目录）；装机流水线 aa start 命令已更新为新包名

### P2 终验（2026-10-06 06:43-06:45，Zodex 实证，通过——协议级全链路）
- **根因链完整查明**：①明文 HTTP 被 KaihongOS 在 @ohos.net.http 层拒绝（http 端点 8ms 瞬断 vs https 端点正常往返的差分实验实证）→ LLM 端点必须 https；②bug-1 机制现场抓获：设备 TextInput 受控值回灌缺陷（值=旧显示+新输入无缝拼接，地址栏实验录得 `search?q=`+新输入）
- **端点配置**：宿主 hmh provider 池批量测试后选用 https://apihub.agnes-ai.com/v1 + agnes-3.0-flash（key 存于宿主 hmh config）；宿主 ollama 不可达路径已废弃（11434 被死链 portproxy 占、原生 ollama 僵死、11435 方案因明文禁令作废）
- **循环铁证（hilog）**：task start → step 1-12/15 连续推进；12× HTTP 200 + tool_calls 解析（navigate/getText/snapshot/wait 全部触达）；tool_result 回灌（messages 2→24 增长）；结束于 HTTP 429 限流（免费端点节奏限制，非代码问题）→ task failed 正确传播
- **遗留到 P5（已记录缺口）**：BCP 工具报「JS Bridge注入失败：WebView未准备好」——agent 的 tab 不出现在标签栏、无 Web 组件挂载；「agent 完成任务并报告页面标题」依赖 P5 的并行 Agent tab（标签栏渲染 agent tab + 后台 Web 挂载）
- 修复项（转 P3 任务包）：isUrl 正则支持端口；LLMClient catch 的 `${e}` 详情未出现在 hilog（ErrorHandler console.error 链路待查）；标签栏渲染 agent tab

## P3 验收记录（编码+构建完成，装机验证待 Zodex 发令）

**日期**：2026-10-06 ｜ **执行**：hmh（本棒仅编码+构建，未装机——VM/daemon 被 oneaiterm 争用）

### A. MCP 网络层（P3 核心）

**A1. service/HttpMcpTransport.ets（新建，~520 行）**
- 基于 @ohos.net.socket TCPSocketServer 的最小 HTTP/1.1 服务，监听 0.0.0.0:{ConfigManager.getMcpPort() 默认 9222}
- **API 版本核对（本机 SDK d.ts 逐一验证，全部 ≤API 14）**：TCPSocketServer.listen/on('connect') since 10；TCPSocketConnection.send/close/on('message') since 10；util.TextEncoder.encodeInto since 7；util.generateRandomUUID since 9；TextDecoder.create since 9
- **唯一风险点**：TCPSocketServer.close() d.ts 标注 @since 20 —— stop() 中已 try/catch 防御，API14 设备若缺此方法仅打 warn 不崩溃
- HTTP 解析：请求行+headers+body（Content-Length 分帧，单连接多请求 keep-alive 循环，guard 32 上限）；headers 超 8KB→431，body 超 1MB→413
- 路由：POST /mcp（JSON-RPC 2.0）；GET /mcp→405+Allow 头；OPTIONS→204 CORS 预检；其他→404
- JSON-RPC 三方法：initialize（result 含 protocolVersion/capabilities/serverInfo + 响应头 Mcp-Session-Id: uuid）/ tools/list（10 工具，name+description+inputSchema，与 MCPServer ToolType 一一对应）/ tools/call（提取 name/arguments 调 delegate，失败=code -32000）
- token 鉴权：query ?token= 走 validateToken，失败 401（token 已从 dispatch 层透传至 callTool，修掉了初版空 token 必 401 的自察缺陷）
- CORS：Access-Control-Allow-Origin: * 全响应携带
- 每请求 console.info 留痕（`[MCP-HTTP] {method} {path} client={id} bodyLen={n}`），hilog 可查
- ArkTS 严格模式合规：JSON-RPC/MCP 响应结构全部显式类（JsonRpcResponse/McpToolDescriptor 等 14 个），无对象字面量直传

**A2. MCPServer 接线**
- start()：真调 HttpMcpTransport.start(port, this)，监听失败→ErrorHandler MCP_004 + return false（删除原「盲 port++ 重试」假启动逻辑）
- stop()：await HttpMcpTransport.stop() 释放端口+连接
- 实现 McpHttpDelegate 接口（validateToken/callTool/getToolNames），HttpMcpTransport 通过接口回调 MCPServer，避免循环 import

**A3. EntryAbility 启动链**
- onCreate：ConfigManager.load() 成功后 generateAuthToken() + MCPServer.start(config.mcpPort, token)，成功/失败 hilog 留痕
- onDestroy：MCPServer.stop() 释放

**A4. scripts/mcp_smoke.py（新建，宿主侧）**
- 6 用例：initialize（结构+Mcp-Session-Id 头）→ tools/list（navigate 在列）→ tools/call(navigate)（content[0].text）→ GET 405 → 错 token 401 → 未知路径 404
- 纯 stdlib（urllib），退出码 0/1；未提供 --token 时自动跳过鉴权后正向用例（token 每次启动随机生成未外发——遗留项见下）

### B. P2 遗留修复

**B1. BrowserShell.isUrl() 端口号**：正则加 `(:\d{1,5})?` 段，http://host:11435/path 类 URL 不再误入搜索

**B2. LLMClient catch 完整异常**：`(e as BusinessError).code !== undefined ? code+'/'+message : JSON.stringify(e)` 属性探测（**根因**：BusinessError 是 interface，ArkTS 严格模式禁 instanceof——原 `${e}` 串接产 [object Object]，这正是 P2 终验错误详情丢失主因之一）；同时补 console.error 直打（不依赖 ErrorHandler 链路）

**B3. agent tab 标签栏渲染**：三处修复——① TabManager.createAgentTab 设 tab.title='Agent xxxxxx'（原空标题）② BrowserShell ForEach 补 keyGenerator (tab.tabId)（无 key 时 ForEach diff 可能不刷新——P2 终验「agent 完成任务报标题」依赖）③ BrowserShell tab 文本兜底：title 空且 agentId 非空显示「代理 {id前12位}」
- 点击 agent tab → TabManager.switchTab + BrowserShell.showDashboard=false → WebViewContent 渲染 → onControllerAttached → registerController（WebViewAdapter）+ BCPEngine.bindWebView → BCP 工具可用（链路既有，本棒补齐入口）

### 构建验证
- hvigor assembleHap **BUILD SUCCESSFUL**（5.5s，33 tasks；错误清零，warn 12 条均为存量：WebViewAdapter may-throw 8 + decodeWithStream deprecated 4）
- 产物：entry/build/default/outputs/default/entry-default-unsigned.hap（装机阶段走 repack API14 → hap-sign-tool → bm install 既有管线）

### 编码期自察修复
- HttpMcpTransport 初版 tools/call 传空 token（MCPServer.callTool 先 validateToken 必 401）→ 改为 dispatch 层真实 token 透传
- sendRpc result 兜底语义错误（error=null 且 result=undefined 时误填 initialize 结构）→ 改为仅显式传参才填
- instanceof BusinessError 全局 5 处编译错 → 属性探测（编译器亲自抓出的 P2 遗留根因）

### 遗留与风险（交装机阶段）
1. **token 外显缺失**：authToken 每次启动随机生成且未写任何外部可见位置。装机验证 mcp_smoke 正向用例前需先补 token 外显（建议：写入 files/mcp_token.txt 或 hilog 固定输出），否则只能跑 401/405/404 负向用例
2. **TCPSocketServer.close() @since 20**：API14 设备 stop() 可能仅 warn 不真正释放端口（连接已逐个 close 防御）——若装机发现端口复用失败，需改为监听 socket 重建策略
3. 9222 端口若被 VM 其他服务占用，start 失败会走 MCP_004 错误日志（不再盲重试）——装机时看 hilog 确认实际监听端口
4. keep-alive 连接在客户端不主动断开时由客户端 close 触发清理；服务端无超时踢除（最小实现取舍）

### P3 终验（2026-10-06 11:0x，Zodex 实证，通过——MCP 核心链路）
- 装机：v10 HAP（P3B 断点收尾由 Zodex 接管：VM 签名 browseros-profile-release.p7b → bm install -r → aa start）
- 监听证据：`[MCP-HTTP] listening on 0.0.0.0:9222` + `[MCPServer] authToken persisted to .../files/mcp_token.txt` + EntryAbility 启动链拉起成功
- 隧道：hdc fport tcp:9222（P3B 已建）+ token（hdc cat 取得）
- 六用例（Node fetch 实测）：initialize ✅ 200+Mcp-Session-Id+serverInfo；tools/list ✅ 200 完整工具表；tools/call(navigate) ✅ 200 + -32000 穿透到 BCP 层（传输层全通）；no-token ✅ 401；**GET /mcp ❌ 挂起（应 405，缺陷转 P4 修）**；tools/call(getText) ⚠️ 工具名不对齐（转 P4 修）
- 里程碑：外部 AI 工具经 MCP Streamable HTTP 真实可连（Claude Code/Cursor 兼容路径打通）
- 已知取舍：keep-alive 无服务端超时踢除（最小实现）；TCPSocketServer.close @since 20 由逐连接 close 防御


## P4 汇报（2026-10-06 12:4x，relay2 执行，Zodex 监督收敛）

### 缺陷修复（两项全通过，实测取证）
1. **GET /mcp 挂起 → 405**：HttpMcpTransport.ets 分帧修复。
   - relay1 假设（findHeaderEnd 找不到 CRLFCRLF）**不成立**——实测 72B 标准 GET 的 CRLFCRLF 能找到、buf 被正常消费，但 dispatch 内部抛异常被吞。
   - 真根因：GET 无 body，decodeUtf8(subarray(n,n)) 对空 Uint8Array 在该 netstack 返回 undefined，bodyText.length 抛 TypeError，async rejection 被 ArkTS 吞掉 → 客户端永久挂起。
   - 修复三件套：空缓冲提前 break（消噪）；(loose || contentLength===0) 时空 body 直接 ''；dispatch(...) 加 .catch 打日志。
   - 另保留宽松 GET 分帧兜底（loose framing）+ findFirstLineEnd 辅助 + header 未找到时 tail=16字节hex 诊断日志。
   - 实测：原始 TCP 探针 GET /mcp?token=abc（72B）→ 立即收到 `HTTP/1.1 405 Method Not Allowed ... {"error":"POST only"}`（修复前同探针 5s 窗口 0 字节）。
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


### P4 终验（2026-10-06 12:5x，Zodex 实证，通过——核心全绿 + 一个转 P5 缺口）
- GET /mcp 405：relay2 实测通过（原始 TCP 探针立即收到 405 + {"error":"POST only"}）；真根因=空 body decode TypeError 被吞（修正 relay1 分帧假设）
- getText 对齐：tools/list 10 工具、tools/call 200、真实 agent operationLogs 有 getText 记录
- 录制管道：会话 JSON 落盘（operationLogs 10/6 条，含 operationType/targetElement/timestamp/result）；3s 定时器 hilog 实证
- screenshots=0 未闭环（Zodex 复验：agent tab 仍不渲染于标签栏——B3 修复不完整）。根因链：agent tab 不渲染 → 无 WebView 挂载 → capture 报 WebView未准备好。闭环归属 P5 并行 Agent tab（该阶段重做渲染层）
- 回放按钮 UI 走查随 P5 后统一验收

---

## P5 接线与打磨 汇报（2026-10-06 15:25 收棒）

### 做了什么
1. **Agent tab 渲染修复（P4 唯一遗留核心缺口）— 根因定位并修复，装机实证**
   - 排查路径：先疑事件链/ForEach，逐步排除——tab event 日志正常、@State 赋值正常（uiTabs=2）、两帧强制重建也执行（rebuild next frame: 2）但 UI 仍只 1 tab
   - **真根因：布局挤压**。tab item 的 Text 带 layoutWeight(1) 而外层 Row 无宽度约束，首个 tab 的 Text 吃满整行，后续 tab 被挤成 4px（uitest dumpLayout 实锤 Row [1371,235][1375,262]）。ForEach 从未失效
   - 修复：tab item Row 加 .layoutWeight(1)（.verify/p5_patch_lw.cjs，node 字节级补丁绕 CRLF）
   - 附带加固：covering 覆盖态标记 + tabsDirty 两帧重建（setTimeout 0），防覆盖态返回后同步残留
2. **装机流水线执行 3 轮**：hvigor build → p5_repack.py (API14) → p5_deploy.cjs（VM 侧 hap-sign-tool browseros-profile-release.p7b 签名 + bm install -r），均成功
3. **B 项接线现状确认**：书签☆/历史🕘按钮已在工具栏（书签 0 条·历史 0 条文案在）；ConfirmDialog 已挂 BrowserShell build() 消费 SENSITIVE_OPERATION_DETECTED；Onboarding 已有首帧路由逻辑（config onboardingCompleted=true，日志证实走 pages/BrowserShell）

### 验证了什么（装机后真实设备证据）
- ✅ 多标签渲染：about:blank + Dashboard + **Agent f8bhw5** 三标签并存，等分宽度（[503-823]/[849-1158]/[1195-1504]），点「+」立即新增 tab
- ✅ Agent tab 标题=代理名（Agent f8bhw5）
- ✅ 点 agent tab → Web 组件挂载：hilog 链 onControllerAttached tab_3 → registered webview adapter → onPageEnd(about:blank)；布局 dump Web 组件出现
- ❌ BCP 工具对活 agent 的端到端：**未完成**。时序竞态——agent 在 NeoDashboard 创建即开跑（~40s 跑完），点回 agent tab 时已结束，期间 BCP 全报 WebviewController must be associated with a Web component。需 agent 存活期间快速切 tab 重验（详见 evidence/p5/RESUME-STATE.md）

### 遗留什么（按优先级）
1. **BCP 端到端**（P4 核心缺口的最后一环）：agent 运行中点 agent tab → BCP navigate/getText/screenshot 成功 → sessions/*.json screenshots>0 → answer 含 Example Domain。修复本身可能不需要改码（Web 已挂上），是 e2e 时序问题；若切 tab 后 BCP 仍报错则查 BCPEngine.bindWebView 与 agent 运行循环的绑定时机
2. P5-3 Dashboard 激活异常复验：本轮三标签切换正常（about:blank/Dashboard/Agent 均可激活），Zodex 报告的旧异常疑已被本棒 covering/tabsDirty 修复覆盖，未专项复验
3. B4 回放入口（NeoDashboard 回放按钮→SessionPlayerPage 截图帧）：未动，依赖 BCP screenshots 非空
4. B5/B6 首启 Onboarding 与支付类 URL ConfirmDialog 触发：代码已在，未专项触发验证
5. C9 暗色主题：未动

### 工程状态
- 源码：entry/src/main/ets/pages/BrowserShell.ets（tab item layoutWeight + covering/tabsDirty）
- 构建：15:01 BUILD_OK → repack entry-p4-api14.hap (224641B, API14) → 已装机
- e2e 工具：.verify/p5_e2e.cjs（dump/inputs/clickxy/type/sleep）、p5_chain.cjs（BCP 链路日志）、p5_tabband2.cjs（tab 栏带状 dump）
- 断点文档：evidence/p5/RESUME-STATE.md


### P5 终验（2026-10-06 15:4x，Zodex 实证，通过——并行 Agent 核心落地 + 组合时序缺口如实记录）
- Agent tab 渲染：P5 破案（布局挤压：tab Text layoutWeight 吃满行，后续 tab 被挤成 4px——一直渲染只是不可见）+ 修复装机实证（三标签等宽并存，标题=代理名）
- Agent tab 点击→Web 挂载：hilog 链实证（onControllerAttached→registered adapter→onPageEnd）
- 书签/历史接线：仪表盘『书签 0 条 · 历史 0 条』+ 工具栏 ☆/🕘 按钮上线
- Agent 循环+录制管道组合再次全链实证：agent 创建→LLM 200×N→tool_calls→addOperationLog（首次实证）→会话 JSON opLogs 完好
- **组合时序缺口**（VM 窗口化+对方项目抢前台所致，非代码缺陷）：『agent 存活期间人工点击其 tab』未能在本环境完成实测，BCP-on-live-agent 与 screenshots>0 的最终组合待条件允许时复验（配方：agent 创建后 60s 内 dump 定位 Agent 标签点击，hilog 看 bindWebView+capture 成功）
- 事故记录：VM 中途崩溃一次（QEMU 进程消失），由 Zodex 用官方快捷方式恢复，双包无损

- [x] P3 MCP 网络层（2026-10-06 终验通过）
- [x] P4 录制回放管道（2026-10-06 终验通过，screenshots 组合时序转 P5 复验）
- [x] P5 接线与打磨（2026-10-06 终验通过，组合时序缺口如实记录）


### P6 终验（2026-10-06 18:2x-18:3x，Zodex 独立复跑实证，通过——完整 Agent 闭环达成）
- 后台并行 Web（治本）：BrowserShell 每非 dashboard tab 各渲染 Web（Hidden 保活）；NeoDashboard 改造为壳内覆盖面板（根治 router 覆盖态不重渲染）
- **零人工干预全链铁证（Zodex 独立复跑）**：建 agent→BCPEngine bound after 1 polls→auto-navigate https://example.com→snapshot/wait/getText 全 success→capture shot#5/#6→LLM finish=stop→**task complete, answer: The page is https://example.com, and its title is:...**→会话 JSON opLogs=5 screenshots=8
- 回放端到端：点『回放』→router 创建 SessionPlayerPage→**loaded session shots=8 logs=5**（neo Replay 卖点真实数据首验）
- B 项：暗色主题 6 处落地；导入登录态诚实提示落地；Onboarding 12 处接线（触发走查留待）；ConfirmDialog P5 已挂载（触发走查留待）
- hmh 会话无 final 中断 2 次（上下文耗尽），Zodex 均接管收尾验证


### P7 终验（2026-10-07 00:0x-00:1x，Zodex 实证，通过）
- **A1 cookies.json 导入全链**：UI 对话框→路径输入→parseCookieJson(cookies=1 domains=1)→**injectCookiesToWebview written=1**（WebCookieManager 真注入）→回显 domains=1 injected=1。关键情报：hdc 视角应用沙盒 filesDir=/data/app/el2/100/base/<bundle>/haps/entry/files（推测试 fixture 的正确路径）
- **B4 MCP GET 405 复验**：{"error":"POST only"} + 405 ✅（fport 隧道由 P7 重建）
- **A2 Onboarding 触发**：config 置 false 冷启动→hilog: entry page: pages/OnboardingPage + RunPage/router 创建记录 ✅（已还原 true）
- **A3 ConfirmDialog**：挂载验证 ✅（mounted, listening SENSITIVE_OPERATION_DETECTED）；端到端触发留走查项（需真实可加载的敏感关键词页面触发 detectNavigation）
- B7 回放视觉/B8 三标签视觉：数据链路已证（loaded shots=8），视觉截图因 agent 列表内存态重启后为空未取样——留走查项
- **C 工程卫生**：97 个调试产物归档 attic/（git mv 保留历史）、__pycache__ 清除、根目录 14 个核心文件、清理后构建绿（1.1s）
- P7 会话无 final 中断（上下文耗尽），A/B 项由 Zodex 接管验证、C 项由 Zodex 执行


### 第三轮查缺补漏终验（2026-10-07 09:2x，Zodex 实证，全部通过——项目完全收官）
- **SensitiveOperationDetector.detectNavigation 修复**（hmh 微任务）：原只查 SETTINGS 类关键词 → 改为 PAYMENT+DELETE+SETTINGS 三类（与 detectClick 对齐）
- **ConfirmDialog 端到端全链**：MCP navigate example.com/pay → onPageEnd → 检测命中 payment → 弹窗（onDetected agent=mcp_http）→ tools/call 正确挂起等人类决策 → 点确认 → onConfirm（requestConfirmation resolve）→ 确认后导航继续、二次检测（每次敏感导航均询问，语义正确）。弹窗视觉：confirm_dlg.jpeg
- **视觉走查全取证**：三标签并存+主体渲染 Example Domain（w3_tabs.jpeg）；暗色主题仪表盘+书签计数动态更新『书签 1 条 · 历史 4 条』（w3_dark.jpeg）；历史面板 4 条（w3_history.jpeg）；书签添加 hilog（bookmark added）
- 已知设备级残留：TextInput 受控回灌缺陷致地址栏输入偶发拼接（设备问题，应用侧已有 sanitize 缓解）
- 状态：BrowserOS neo 七卖点全部落地并逐一实证；项目计划全部结束


---

## P8：桌面快捷启动 + 官网 UI 一比一复刻（2026-10-07，用户点名的两大缺口）

### 根因与机制（Zodex 实测破解）
- **桌面快捷机制**：launcher=com.ohos.launcher；布局库 /data/app/el1/100/database/com.ohos.launcher/entry/rdb/（DesktopItem.db + AppDockTable.db）；桌面=Docs Desktop 目录视图，图标=*.app JSON 描述符+DB 行；**桌面网格只渲染 x=0 列**；force-stop 后 ~2s 自启 → 改库必须单条 shell 原子完成；交互=双击启动
- **图标加载根因**：API26 工具链产出的 resources.index 为 RestoolV2 6.1.0.003，API14 设备 resourceManager 解析失败 → launcher DesktopImageLoader 9001001 → 桌面图标点击中断。需 V1 格式（Restool 5.0.1.011）；本机 API14 SDK：D:\OHOS-QEMU\sdk-5.0.2\14
- 嫁接实验（oneaiterm V1 索引换装）证实根因后 hmh 落地正规修复

### 交付（hmh 三会话，两次上下文耗尽由验收方接续收尾）
- tools/build_v1_hap.py：restool 5.0.1.011 重编 V1 索引（module.json 符号引用数字化+AppScope 合并）→ 装机 HAP 索引头=Restool 5.0.1.011 实测
- tools/add_desktop_shortcut.py：桌面快捷部署（描述符+DesktopItem x0y6+AppDockTable+原子序列）
- tools/install_p8.py：装机编排
- 图标：BrowserClaw logo 多尺寸 48/96/192/216
- UI 复刻（对齐官网四屏）：C1 新标签页（产品名+副标题+三入口）、C2 MCP 安装板（端点 hero+Copy/Docs+五 harness Connect 网格）、Cockpit（三列马赛克+渐变 hero+代理磁贴+最近会话）、回放播放器（视口+播放/停止+倍速+进度条+操作时间线）
- 缺陷修复：P8 重构曾把创建代理表单孤儿化（showLlmSettings 死状态）→ 已移植表单常驻驾驶舱（LLM 接入+创建并启动代理）

### 验收实证（evidence/p8/）
- 桌面：BrowserClaw 图标渲染于左列+任务栏同步；双击启动 pid 实证；hilog 无 9001001
- e2e：表单创建 p8z-e2e（agnes-3.0-flash）→ 自动导航 example.com → 7 步 → task complete 答案 Example Domain
- 四屏截图：desktop_with_shortcut / c1_newtab / s2_cockpit_live_tile（1 代理 1 会话+磁贴+▶回放）/ s3_mcp_install_board / s4_replay_player（shots=11 logs=6）
- 已知残留：设备 IME/TextInput 缺陷使自动化填表需英文+无空格（设备级）；MCP board Connect 为复制配置反馈
- 状态：用户点名的两大缺口闭环；P1-P7 回归（agent 闭环）通过


## P9 全界面/菜单/图标一比一复刻（2026-10-07 收官）

**目标达成**：UI 复刻从四大屏扩展到全部菜单/界面/功能/图标。4 个 feat commit 全部构建装机实测通过。

### 交付清单
- **p9a (cbc4414)** 浏览器 chrome 补全：⋮ 三点主菜单(分组：新建标签页/新窗口|历史/书签/下载|设置/帮助|退出)、omnibox 安全锁(https 绿锁/普通灰 ⓘ)+聚焦建议下拉(历史+书签匹配 图标+标题+URL)、星标 Bookmark 气泡(名称编辑+完成/删除)、工具栏图标统一 20vp #5F6368、标签条 favicon 占位方块+当前标签白底上圆角。新组件 ChromeWidgets.ets(ThreeDotMenu/OmniboxSuggestions/BookmarkBubble)。
- **p9b (57dc4f0)** Agent 侧栏：工具栏 ❐ 切换按钮，右侧 360vp 常驻面板(Agent 标题+agnes-3.0-flash 模型循环下拉+⚙)，消息气泡列表(用户右蓝泡/系统左灰卡)，底部多行输入+发送(=AgentEngine.createAgent 驱动活动 tab，与 Dashboard 磁贴联动)。新组件 AgentSidePanel.ets。
- **p9c1 (5b10017)** 设置页 SettingsPage：左 240vp 导航(AI 与 Agent/外观/隐私与安全/MCP/关于)+右卡片。LLM 表单(端点/Key/模型+保存/测试连接)迁移自 NeoDashboardPanel 模式；MCP 节复用 getMcpEndpoint+Copy；外观=深色开关；隐私=敏感操作确认开关+本地数据说明；关于=版本/构建/返回。
- **p9c2 (0ab6a64)** 历史/书签/下载页：HistoryPage(搜索+按日期分组(今天/昨天/日期)+favicon+标题+URL+时间，agent 会话组 ▶ 回放直达 SessionPlayerPage)；BookmarksPage(列表+行内编辑保存+删除)；DownloadsPage(如实空态：未内置下载管理器，列表结构已就绪)。新窗口=菜单项退化为新建标签页(如实记录)。main_pages.json 注册 10 页。
- **p9d (493e5d8)** omnibox 识别 browseros://settings|history|bookmarks|downloads|newtab 内建 scheme 路由；全局色板统一 #F1F3F4 chrome/#FFFFFF 内容/#5F6368 文字图标/#1A73E8 强调蓝/卡 8-12px 圆角/分隔 #E0E0E0。

### 验证证据（evidence/p9/）
8 张截图(01-initial/02-menu-open/04-agent-panel/05-settings/06-bookmarks(书签)/07-history/08-downloads/03-relaunch) + uitest dumpLayout 布局验证(菜单 7 项全部渲染、设置页左导航 5 节+表单、侧栏 Agent/agnes-3.0-flash/发送、历史页今天分组+about:blank 条目、书签/下载空态)。hilog 菜单路由日志(menu action: bookmarks/history/downloads 全通过)。

### 技术要点
- 构建链不变：hvigorw → tools/build_v1_hap.py(V1 index repack，P4 教训：改码后必须 repack) → tools/install_p8.py(VM 签名装机) → tools/add_desktop_shortcut.py。
- ArkUI 约束：ForEach itemGenerator 内不能写命令式赋值(日期分组改为预计算 GroupedEntry[])；@Builder 多根子节点会掉进布局流，覆盖层必须挂 build 根 Stack。
- P6 红线守住：多 Web 常驻架构未动，tab layoutWeight(1) 保留，覆盖态两帧重建逻辑未触碰。
- uitest inputText 会与已有框值拼接导致 omnibox scheme 实测受阻（代码分支与菜单路由同构已验证）。



### P9 独立验收（Zodex，2026-10-07 20:4x-20:5x，全项通过）
- 装机 20:36 构建；桌面快捷在位；冷启动 pid 实证
- 工具栏：ⓘ 安全图标 + ☆/🕘/⌂ + **❐ 侧栏切换 + ⋮ 菜单**（均实测可见）
- ⋮ 菜单展开：＋新建标签页/⧉新窗口/🕘历史/★书签/⭳下载/⚙设置/?帮助/⏻退出——8 项全带图标（z-accept-menu-open.jpeg）
- 设置页：左导航 🤖AI 与 Agent/🎨外观/🔒隐私与安全/🔌MCP/ℹ️关于 + LLM 表单（预填 agnes）+ 保存/测试连接（z-accept-settings.jpeg）
- Agent 侧栏：Agent 标题+模型下拉 agnes-3.0-flash+⚙/×、任务输入占位+发送、"N 个代理在跑"状态行（z-accept-agent-panel.jpeg）
- 已知交互残留：router 内建页（设置等）物理返回键不回 BrowserShell（keyEvent 137 无效，需冷启动或菜单切换）；后续可加左上返回按钮

## P9r 修复（hmh，2026-10-07 21:4x-22:3x，全项装机自测通过）

**Zodex 缺陷修复：冷启动历史页 agent 会话为空**
- 根因：SessionManager.activeSessions 纯内存 Map；stopRecording 先写盘再 delete 内存；getSessionList() 只读内存，磁盘 13 份 ses_*.json 完全不可见（清偿 P4「重启丢历史」债）
- 修复（service/SessionManager.ets）：
  - 新增 persistedSessions 磁盘会话缓存 + ensurePersistedSessions() 异步枚举 sessions/*.json（StorageManager.listDir，screenshots 置空省内存，回放走 getSessionDetail 重读盘）
  - getSessionList() 改为「活跃内存 + 磁盘历史」合并去重（sessionId，活跃优先，startTime 降序）
  - 新增 getSessionListAsync()（懒加载触发，规避早于 EntryAbility.setBasePath 的时序竞态）
  - deleteSession/stopRecording 同步维护 persistedSessions（删除即剔除；结束即入列）
- HistoryPage.reload() 增加异步二段刷新（磁盘就绪后重渲染）
- 实证：hilog `persisted sessions loaded: 13` + `HistoryPage sessions refreshed: 13`；dumpLayout 历史页「代理会话」分组 13 条全渲染、每条带「▶ 回放」；点击回放进 SessionPlayerPage（`loaded session=ses_1791372301051 shots=11 logs=6`）

**次要修复 A：?帮助 菜单**
- 原实现 case 'help' 打开 NeoDashboard 侧栏（名不副实）；改为 createNewTab + navigate https://www.browseros.com（真实 Web 标签）
- 实证 hilog：menu action: help → new tab created → navigate to https://www.browseros.com → loadUrl dispatched → onPageBegin url=https://www.browseros.com/

**次要修复 B：设置页左上 ← 返回钮**
- P9 验收已知残留（物理返回键不回 BrowserShell）；SettingsPage 左导航顶部加 ← router.back()
- 实证：dumpLayout ← [86,38][116,71] 可见，点击后回 BrowserShell（地址栏 https://www.browseros.com 助证同帧状态）
- 其余三内建页（History/Bookmarks/Downloads）本就有 ← 返回钮（P9 已验收）

构建链：harmony_build(BUILD SUCCESSFUL) → tools/build_v1_hap.py(V1 repack 360530B) → tools/install_p8.py(VM 15566 sign+install+launch OK)。
证据：evidence/p9/z-p9r-history-persisted.jpeg、z-p9r-help-tab.jpeg、p9r_1..13 系列截图；hilog 详录 .verify/p9r_h*.txt。
备注：VM 上 com.oneaiterm.terminal 反复抢前台（未处置，任务书禁动 oneaiterm）；验证以 hilog+dumpLayout 铁证为准。


### P9r 独立验收（Zodex，2026-10-07 22:4x-22:5x，全项通过）
- **持久化会话列表**：冷启动 → 菜单→历史 → "代理会话"组列出 9+ 个磁盘历史会话（agent_id+步数+时间+▶回放）；点击回放 → SessionPlayerPage `loaded session=ses_1791372301051 shots=11 logs=6` 播放器完整（跨重启会话回放全链闭环，P4"重启后无会话入口"UX 债了结）——z-accept-p9r-history-persisted.jpeg
- **帮助菜单项**：⋮→帮助 → 新建标签 + 🔒 + 10% 进度导航 https://www.browseros.com——z-accept-p9r-help-navigating.jpeg
- 设置页返回钮已修（hmh）；历史页 ← 返回实测可用
- git 5716614


### 终回归（Zodex，2026-10-08 02:0x，p9r 最终构建全链绿）
- **Agent 闭环**：驾驶舱表单建 p9final-reg → example.com → 6 步 → task complete 答案 Example Domain（agnes-3.0-flash）
- **MCP 外部连接**：fport 9222 + 新 token → initialize HTTP 200 + Mcp-Session-Id + serverInfo browseros-kaihong/1.0.0
- **桌面快捷**：force-stop 后双击桌面图标 → pid 8008 拉起（z-final-regression-launched.jpeg）
- 过程注记：跨午夜 hdc 一度掉线（kill/start/tconn 恢复）；VM 重启致窗口化坐标漂移，回归全程 dump 驱动
- **结论：P1-P9+r 全部能力在最终构建上无回归，项目收官**


---

## P10：第四轮审计修复——设置页三处半接线转真 + 死页清理（2026-10-08）

### 审计发现（Zodex 源码排查）
SettingsPage 三处"有 UI 无接线"：①外观暗色开关只改本地 state（安慰剂）②隐私敏感确认开关未接线③测试连接只查配置完整性不发真实请求；另 main_pages.json 注册的 DashboardPage/NeoDashboardPage/TestPage 三页零引用。

### 修复交付（hmh 一棒完成代码与装机，自测归档中断由验收方接续）
- 新增 common/Palette.ets 全局色板（浅/深双色板：chrome #F1F3F4→#202124、内容白→#292A2D、文字→#E8EAED 等）；AppStorage('darkMode') 分发 + BrowserShell/侧栏/驾驶舱/内建页全表面消费；AppConfig 增 darkMode/sensitiveConfirm 字段持久化
- 测试连接=LLMClient 真实 HTTP 往返（最小 ping 消息 15s 超时），显示 模型+耗时
- 敏感确认开关接入 ConfirmDialog 链（off 时 MCP/agent 敏感操作直接执行不再挂起——行为已在 DEVPLAN 如实记录）
- 死页三件删除（NeoDashboardPage 表单早已移植进面板），构建绿

### 独立验收（Zodex，2026-10-08 07:0x-07:1x，全项通过）
- **暗色即时切换**：设置→外观→开→浏览器工具栏/标签条/新标签页全深色（z-dark-on.jpeg，视觉分析确认 #202124 系+浅字）
- **暗色持久化**：toggle 后 config.json 立即 darkMode:true，冷重启 EntryAbility 读回 true 且界面保持深色（z-dark-persist-coldstart.jpeg）
- **测试连接真往返**：`✓ agnes-3.0-flash 连接成功 (8551ms)`（真实 HTTP 往返+延迟显示）
- **隐私开关联动**：root 推 sensitiveConfirm=false → MCP navigate example.com/pay **5ms 直接执行 200**（对照 P8 同操作挂起等弹窗）→ 验后已恢复 true 默认
- UI 点 Toggle 的 uitest 命中在隐私节偶发不稳（设备级自动化残留；源码 onChange→ConfigManager 接线已确认，同款暗色 Toggle UI 交互已实测可用）
- git 见本轮提交

---

## P11 全界面复刻补缺（2026-10-08，五棒接力收官）

### Phase 交付（git 分笔）
- **p11a (be794e6)** 图标体系：28 枚 Material SVG（ic_back/forward/reload/star/history/home/search/globe/folder/close/add/more_vert 等，24x24 无 fill 属性），全工具栏/菜单/标签条字形图标换 SVG 双态染色（fillColor + darkMode Palette），V1 index 同步（restool 5.0.1.011，media records 45）
- **p11b (b98c140)** Chromium 标签条：TabStrip 组件（favicon 占位 + 标题 12px + × 关闭，当前标签上圆角 8px 白底，item layoutWeight(1) 等分——P5 挤压教训固化）+ TabSearchPanel（Ctrl-K 式标签搜索：标题/URL 过滤 + 行内 × 关闭 + 新建项）
- **p11c (b997a53)** 右键菜单：ContextMenu 自绘覆盖层（拦截 Web.onContextMenuShow return true），页内菜单=后退/前进/重新加载/加入书签/复制网址/查看源码（ViewSourcePage 内建页），tab 菜单=向右新建/重开已关闭/复制网址/关闭/关闭其他/关闭右侧；仪表盘区=刷新/后退/书签管理。设备无物理右键 → 以长按触发（device-specific 决策）
- **p11d (9a53886)** 书签条 + omnibox 分组下拉 + 书签气泡：BookmarkBar 组件（仅 dashboard/neo 显示，pill 项 ic_globe+标题，右端「全部书签 N」→ BookmarksPage，点击=当前标签跳转），OmniboxSuggestions 首行「搜索 kw」+ 历史/书签组头，onPick(kind,url) 搜索项走引擎 fallback，BookmarkBubble 加「文件夹:书签栏」只读行（模型无层级如实标注）；修复存量 bug：BookmarkManager.load() 冷启动无人调用→书签重启即丢（aboutToAppear 接线）；omnibox scheme/右键快捷文案字形去 glyph 化（Alt+← 改 Alt+左箭头）
- **p11e** 收尾提交（本 DEVPLAN 节 + 证据归档）

### 设备实测决策与限制（如实记录）
- 右键=长按：KaihongOS 5.0 无物理鼠标右键事件，Web.onContextMenuShow 经长按菜单路径触发
- ArkUI 约束再验证：ForEach itemGenerator 禁命令式赋值（日期/分组预计算）；@Builder 多根子节点掉进布局流（覆盖层挂 build 根 Stack）；tab item .layoutWeight(1) 红线保持
- 设备 IME/TextInput 受控回灌缺陷（P2 已知）持续存在，omnibox 自动化输入偶发拼接，验收以 dumpLayout + hilog 铁证为准

### 证据（evidence/p11/）
p11a-icons*/p11b-*（标签条 shape + tab-search）/p11c-*（右键菜单三屏）/p11d-dashboard + p11d-bar-crop（书签条 3 pill）/p11e-bookmarkbar、p11e-omnibox-dropdown（分组下拉）、p11e-bookmark-bubble（文件夹行）、p11e-bookmark-open、p11e-threedot-menu、p11f-boot（终棒装机复验：书签条+驾驶舱全渲染）。

### 遗留（转 P11-F 用户指令补缺）
1. Web 引擎层：停止按钮（加载中刷新钮切 stop 态）——p11f 执行
2. 键盘拦截（Ctrl+L/R/T/W 等 onInterceptKeyEvent）——p11f 执行，不支持组合键在 DEVPLAN 如实记录


### P11 独立终验收（Zodex，2026-10-08 19:4x，全项通过，git 链 be794e6→b98c140→b997a53→9a53886→41c4b06→482f7a6→3768046）
- **A 图标体系**：29+ 枚 Material 风 SVG（fillColor 双色板染色）；终构建 dump 实证工具栏/标签条无任何文字字形残留（p11z.json 无 ←→↻☆🕘⌂❐⋮ 文本节点）
- **B 标签条**：Chromium 化（favicon 方块+标题+TabSearchPanel+工具栏透明按钮）
- **C 右键菜单**：ContextMenu 组件+标签/仪表盘长按+Web.onContextMenuShow 页面菜单+ViewSourcePage（设备适配：右键=长按）
- **D 书签条**：终构建实测 3 pill（华为开发者/OpenHarmony/Example Domain）+全部书签 3 入口（p11z1.jpeg）
- **E**：omnibox 分组下拉/书签气泡文件夹行/字形清零/全表面截图 evidence/p11/
- **F Web 引擎层补缺（用户任务书）**：停止按钮双态（isLoading→ic_stop→Adapter.stop() 透传+手动复位，构建绿+装机）；onInterceptKeyEvent Ctrl+L/R/T/W 代码落地（SDK14 web.d.ts:7511 实锤 since9 兼容；**设备级限制如实记录：VM uinput 无法注入 Ctrl 组合键，代码路径编译通过但实操不可验证**）；用户任务书 12 项全部闭合（10 项 P1/P6 既有+2 项本轮补齐）
- 附注：482f7a6 后工作树遗留 9 文件图标清理（P11G 死前未提交，含 Image 上残留 .fontColor 编译隐患 3 处）由 Zodex 修复提交（3768046）并构建绿+装机；期间曾发现外来任务（tty7 安装）插队占用 daemon，无仓库污染


---

## P12：Agent 引擎规格收尾——SSE 流式 + 紧凑 Markdown 快照（2026-10-08/09，用户 Agent 引擎任务书比对后真缺口）

### 规格比对结论
用户任务书 17 项中 15 项 P2/P6 已交付（任务循环/15 步上限/tool_calls 解析/六工具 navigate+click+type+scroll+snapshot+waitFor/http.createHttp/OpenAI/Bearer/结果回灌循环）。真缺口=SSE 流式与快照紧凑化，本轮补齐（hmh 两棒上下文耗尽无产出，Zodex 接手实现——收敛优先）。

### 交付（git 52cc10b + c7d38c8）
- **p12a SSE 流式**：LLMClient.chatStream（http.createHttp + on('dataReceive') 增量收帧、util.TextDecoder 跨块解码、跨帧残留缓冲、data: 行解析、[DONE]、delta.content 拼接、delta.tool_calls 按 index 增量合并、Accept: text/event-stream）；AgentEngine 主循环流式优先，onDelta 实时更新磁贴"思考中"活动文本；**健壮降级**：无有效 delta/HTTP!=200/异常 → 自动回退非流式 chat 重试（hilog 记录）
- **p12b 紧凑 Markdown 快照**：JSBridgeInjector `__bcp_snapshot_md`（页面侧 clone body→过滤 script/style/noscript/template/iframe/svg/canvas/form/link/meta→可见性过滤（display:none/visibility:hidden）→h1-h6 转 # 标题、a 转 [text](绝对href)、li 转 - 列表、button 转 [按钮 x]、img alt 转 [图: x]、table 转竖线行→30000 字符截断）；**同步 return + runJavaScript 表达式求值直取**（不依赖 registerJavaScriptProxy 回调——该 proxy 换页后失效是 MCP 冷调 snapshot 旧 bug 根因）；BCPEngine.snapshotMarkdown 带"函数丢失自动重注入+双引号解包+__SNAP_ERR__ 错误透传"；SnapshotGenerator 统一透传（根治旧 compress(null.tag) 崩溃）；AgentEngine snapshot 工具与 MCP snapshot 工具双双切换
- **e2e 实证**：①流式→降级链：POST(stream)→SSE headers→（agnes 免费端点帧不标准/429 限流）→自动非流式 200→tool_calls 派发→循环续跑至 step 6+ ②快照格式：MCP 直调 navigate iana.org/help/example-domains → snapshot 返回 `# Example Domains` 标题行 + `- Domains/- Protocols` 列表行 + 段落文本——紧凑 Markdown 结构成型（example.com 2026 改版已无 h1，故换 iana 验证标题分支）
- 设备级注记：agnes 免费端点 SSE 帧格式与其限流策略导致流式常走降级路径——降级保障了功能不回归；端点升级后流式自然生效

---

## P13: MCP WebSocket 传输端点（8765）——用户 MCP 服务端任务书真缺口补齐（2026-10-09）

### 技术决策记录
- **@ohos.net.webSocket 仅客户端**（createWebSocket 连出），API14 无 WS 服务端 API → WS 服务端自建于 @ohos.net.socket TCPSocketServer（HttpMcpTransport 同款模式）
- 9222 Streamable HTTP 端点保留不动（MCP 现行标准传输）；WS 为任务书指定 8765 补充端点，同一 JSON-RPC 核心 McpJsonRpcCore.ets（从 HttpMcpTransport 平移抽出，HTTP 行为等价）
- 敏感确认链不在 WS 层重复实现——callTool 内 SensitiveOperationDetector 走页面层 ConfirmDialog，与 HTTP 端点同语义

### 交付
- **service/McpJsonRpcCore.ets**（新建）：initialize/tools/list/tools/call 分发核心 + 10 工具描述表 + RpcOutcome（传输层无关的响应载体），HTTP/WS 双端共用
- **service/WsMcpTransport.ets**（新建）：握手（GET /mcp?token= + Upgrade → 101 + Sec-WebSocket-Accept=Base64(SHA1(key+GUID))，公式宿主 node 先行验证）→ 客户端帧 mask 解析（126/127 长度扩展 + XOR 解码）→ opcode 分发（0x1 text=JSON-RPC、0x8 Close 回显后清理、0x9 Ping→0xA Pong、0xA 忽略、0x0 continuation 如实记录不支持）→ 服务器帧不掩码编码（util.TextEncoder UTF-8）→ Map<sessionId,conn> 多客户端会话管理、断开清理、响应单播
- **HttpMcpTransport.ets 瘦身**：JSON-RPC 核心改 import McpJsonRpcCore（re-export McpHttpDelegate 保持兼容），HTTP 分帧/路由/鉴权原地保留——回归实测 initialize 200 正常
- **接线**：MCPServer.start(port, token, wsPort=8765) 同起双传输（WS 失败不阻断 HTTP）；stop 同停；AppConfig 增 wsPort 字段（默认 8765，tolerant read，1024-65535 校验）；EntryAbility 传 config.wsPort
- **tools/p13_ws_test.cjs**（新建）：node 原生 net 手写最小 WS 客户端自测（握手→initialize→tools/list→navigate→Ping/Pong→Close 回显）

### 实测（evidence/p13/，2026-10-09 01:10-01:12 装机后）
- hilog: [MCP-WS] listening on 8765（MCPServer.start 同起）
- 自测 6/6 PASS：handshake-101（accept key 验证）/ initialize serverInfo=browseros-kaihong/1.0.0 / tools/list 10 工具 / tools/call navigate 返回 {url,result=https://example.com}（BCP 真实执行，后台 WebView 生效）/ ping-pong 回显 / close 帧回显
- 负向：错 token 握手 → HTTP/1.1 401 Unauthorized（发完即断）
- 回归：HTTP 9222 initialize 200 正常（MCP-RPC via=mcp_http 铁证）
- 注记：navigate 后屏幕截图显示 Dashboard——激活 tab 是仪表盘，导航发生在绑定 WebView（P6 多 Web 常驻架构），RPC 响应即执行证据


### P13 独立验收（Zodex，2026-10-09 01:1x，全项通过，git ada6c02）
- 宿主手写最小 WS 客户端（.zcode/p13_wsclient.cjs：net 原生握手/掩码帧/服务器帧解析）连 8765：
  **PASS 101 握手且 Sec-WebSocket-Accept 密钥校验 VALID**（SHA1+magic GUID+Base64 公式正确）→ initialize `browseros-kaihong/1.0.0` → tools/list **10 工具** → **Ping→PONG** → Close 回显 → ALL-PASS
- 双端点并存回归：9222 Streamable HTTP initialize 200+serverInfo 无回归（同进程同时服务）
- 设备日志另证 hmh 自测路径：text frame/ping→pong/close echo/client 清理全过
- 架构：McpJsonRpcCore.ets 抽出 JSON-RPC 分发核心，HTTP/WS 双传输共享（敏感确认链沿用页面层 ConfirmDialog 语义，P8/P10 已验收，不重复实现）
- 技术决策记录：@ohos.net.webSocket 仅客户端（API14 无服务端 API）→ WS 服务端自建于 TCPSocketServer；9222 HTTP 为 MCP 现行标准传输保留为主端点


### P14 独立验收（Zodex，2026-10-09 02:3x-02:5x，全项通过，git 5fbf1e4）
- **历史 RDB 持久**：冷启动历史页 **13 条**（z-history-13-persisted.jpeg）；history.db+idx_visit_time 落盘+WAL 活跃；hilog `HistoryDb init ok` + `loadHistory done`
- **登录态 Preferences**：`PrefsStore login_state ready` + 冷启动 `domains=1` 装载；.migrated 档案存在（一次性迁移完成）
- **会话元数据 Preferences**：启动对账 `session index reconciled: 16`（p14d 上移到 EntryAbility，此前惰性）
- **书签订阅**：BrowserShell 订 BOOKMARKS_CHANGED（p14b fix 提交内已接，断点遗留清单过时）
- **搜索 RDB 接线**：HistoryPage 关键词改走 HistoryManager.searchHistory（RDB LIKE，此前内存 filter 只覆盖前 200 条）——p14d 由验收方补
- 已知小残留：新标签页"历史 N 条"计数在 loadHistory 异步完成前渲染首帧可能显示 0（历史页本体正确，时序性显示问题）
- 期间插曲：外来 tty7 任务窗口抢前台，最小化+最大化恢复后照常验收（双项目抢前台既有对策）


---

## P15：会话回放规格收尾——操作类型图标 + 进度条节点标记（2026-10-09，用户回放任务书比对后真缺口，git e413fc4）

### 规格比对结论
用户回放任务书 3 域：①录制链（addOperationLog 每操作 {timestamp,operationType,targetElement,result}+html2canvas 定期截屏+沙箱 sessions/*.json）P2-P6 已交付并多轮实证（shots=21/logs=6 复现）②图片序列+时间轴滑块+倍速（任务书第二路线）P4 起交付 ③垂直时间线列表——已有，**真缺口=操作类型分图标+点击步骤跳转+进度条操作节点标记**。

### 交付（Zodex 直接实现）
- 6 枚操作 SVG（ic_op_navigate/click/type/scroll/snapshot/wait，Material 风 24px fillColor 染色）+ opIcon() 映射（back/forward 归导航、wait_for 归等待、缺省 ic_check）
- **进度条操作节点标记**：Stack 叠层，标记按 (log.timestamp-session.startTime)/duration 百分比 position 定位（clamp 97% 防右溢出），16vp 热区+5vp 蓝点，点击 seekTo 对应时刻
- 时间线列表项加图标列+整行 onClick 跳转对应回放位置
- V1 repack 三步同步（p11_add_svgs_v1.py：39 svg/52 records）

### 验收
- hilog：`loaded session shots=21 logs=6` + `marks built: 6`
- 视觉分析实证（z-replay-marks-icons.jpeg）：进度条 6 个蓝点位置分布正确；时间线六行图标形状与语义一一对应（箭头/指针/键盘/滚动箭头/相机/时钟）；播放控制齐全
- 构建插曲：hvigor daemon 卡死一次（java 0.9% CPU）→ 杀进程 --no-daemon 重跑 4s 绿


---

## R5：第五轮审计——死代码清理 + 计数时序修复 + 终回归（2026-10-09，git 7b7eb93）

### 审计与修复
- **死代码 5 组件删除**（-588 行）：AddressBar/AgentCard/ConnectionPanel/SessionList/TabBar——均被后继取代（TabStrip/ChromeWidgets/历史页等），字符串级二次确认零引用（BrowserShell 命中为同名 @Builder 非组件）
- **新标签页历史计数首帧显 0 修复**（P14 已知残留）：EventBus 新增 HISTORY_CHANGED；HistoryManager 在 loadHistory 完成+recordNavigation 后 emit；BrowserShell 计数改 @State 订阅驱动（书签计数同链复用 BOOKMARKS_CHANGED）

### 终回归（R5 构建全绿）
- **MCP WS 8765**：宿主 WS 客户端 ALL-PASS（101+密钥 VALID+initialize+tools/list 10+Pong）
- **MCP HTTP 9222**：initialize 200+serverInfo
- **桌面快捷**：force-stop 后双击图标 → pid 1587 拉起
- **工具链+事件链联验**：MCP navigate iana → 200 → 历史计数 **17→19 实时+2**（时序修复与 HISTORY_CHANGED 事件链一并实证）
- 冷启动新标签页 `书签 3 条 · 历史 17 条`（修复前显示 0）

### 项目终态
P1-P15+R1-R5 全部收官。五份规格任务书 60 项全闭合。剩余已知项均为设备/端点级（VM 键盘注入、agnes 免费限流、IME 回灌），代码侧无未修缺陷。


## P16 (2026-10-09): R6 audit gaps - downloads / tab restore / onboarding palette

**A 下载 (commit 6c4d8d6)**
- new service/DownloadManager.ets: @ohos.net.http requestInStream -> files/downloads/, (n) conflict suffix, dataReceive incremental write, headersReceive content-length, DOWNLOAD_CHANGED EventBus (500ms throttle), dir-scan restore, retry/cancel/cleanup
- SDK fact: OnDownloadStartEvent = {url,userAgent,contentDisposition,mimetype,contentLength} - NO suggestedFileName (SDK14 web.d.ts since 12); filename derived: contentDisposition filename*/filename= -> url last segment -> download_<ts>
- BrowserShell: Web.onDownloadStart wired; DownloadsPage real list (progress bar, size, copy-path w/ pasteboard, retry, cancel); download indicator button (ic_download + amber dot) while active

**B 会话恢复 (commit dafdc0d)**
- TabManager: Preferences tabs_state {id,title,url,isDashboard,agentId} x max 8, dashboard first; persistTabs + 500ms throttled schedulePersist hooked into createTab/createAgentTab/switchTab/closeTab; restoreTabs() rebuild before loadContent; takeRestoreUrls() consumed by BrowserShell restoreUrlMap -> onControllerAttached loadUrl
- EntryAbility: DownloadManager.init(context) + TabManager.setContext + restoreTabs before entry page decision
- verified: force-stop -> relaunch => 'restoreTabs: 1 tabs' + 'BrowserShell tabs loaded: 1' (was 0 pre-P16)

**C Onboarding palette (commit 5ccac19)**
- OnboardingPage: @StorageProp darkMode + pal(); 40 refs swapped (#FFFFFF->surface, #F8F8F8->surfaceAlt, #EEEEEE->surfaceInput, #333333->text, #666/#999/#BBB->text2, #007DFF->accent, step indicator->accent/border)

**pipeline**: hvigorw (BUILD SUCCESSFUL 6s) -> tools/build_v1_hap.py -> tools/install_p8.py (INSTALL+LAUNCH OK); no new svgs needed (reused ic_download/ic_close/ic_content_copy/ic_check)
**evidence**: .verify/p16_hilog_restore.txt (restore logs), .verify/p16_layout1.json



### P16 独立验收（Zodex，2026-10-09 11:5x-12:1x）
- **B 会话恢复（核心项 PASS）**：`tabs_state` Preferences 落盘（XML tabs 数组）；UI 点 + 新建标签 → prefs 计数 1→2（节流持久化实时）；force-stop 冷启动 → `restoreTabs: 2 tabs` + 标签条两等宽标签渲染——多标签持久恢复全链实证
- **A 下载（代码/接线 PASS；端到端触发=设备级限制如实记录）**：DownloadManager init 日志正常、目录 files/downloads/ 建立、onDownloadStart 已挂全部 Web 组件（回调含 contentDisposition 三级文件名推导）。**但该 VM 的 ArkWeb 内核不触发下载回调**：codeload attachment 的 location.href 导航、宿主页面 `<a download>` 合成 click 均无 onDownloadStart 日志（hilog 全程无触发记录）——与 VM 键盘注入限制同类，真机/完整内核预期可用；DownloadsPage 真数据 UI 就绪（进度/重试/取消/复制路径）
- **C Onboarding Palette**：@StorageProp('darkMode')+Palette 全接（40 refs）；端到端不可见（onboarding 已完成态不显示），代码级验收
- TabStrip 布局事实：+ 按钮实际热区中心 ≈(1558,85)（ic_add 在 tab-search 左侧）


---

## P17：R7 审计三缺口——导航错误横幅 + About 动态版本 + 页内查找（2026-10-09，git a354692）

### 交付（hmh 主体 + Zodex 三层根因攻坚）
- **A 导航错误横幅**（端到端全绿）：onErrorReceive 主文档判定 → 顶部红底横幅（URL+错误码+重试+关闭）。攻坚链：①URL 尾斜杠归一化②导航目标改 lastNavUrl（onPageBegin 记录——MCP/agent 路径不设 pendingUrl）③外层 activeTabId 门槛放宽（P16 会话恢复致 activeTabId 与视觉活动标签错位，诊断行实锤 `active=tab_1_1791516635535` vs error tab_1_1791518385307）④dashboard 覆盖态也显示。实证：invalid 域导航 → UI `加载失败：ERR_INTERNET_DISCONNECTED` + 重试按钮（z-error-banner.jpeg）
- **B About 动态版本**：bundleManager versionName（实测 **1.1.0**）+ 构建行改静态事实 'KaihongOS · API 14'（不再过时）
- **C 页内查找**：⋮ 菜单「查找」项（实测存在，z-menu-find-item.jpeg）+ FindBar 组件（ic_find+输入+上/下 ic_arrow_up/down+关闭）+ BCPEngine findText（window.find 表达式求值，unsupported 如实降级）；dashboard tab 显式跳过（find skipped 日志）。端到端视觉验证受多标签绑定/活动状态机边缘态所阻（自动化环境限制，如实记录）
- **连带 bug 修复**：dashboard 标签被导航到真实页面时自动切 web 模式（此前地址栏=iana 视觉仍是 dashboard 覆盖——P16 会话恢复的双重身份边缘态）

### 遗留记录
- FindBar 端到端视觉验证待真机/手动环境（多标签绑定状态机在 uitest 环境的边缘态）；代码链路完整
- navErrDiag 诊断日志保留（hilog 观察友好）

## P18：搜索引擎完整功能——引擎注册表+设置切换+默认引擎持久化（2026-10-09）

### 交付
- **A 引擎注册表**（common/SearchEngines.ets 新建）：SearchEngine 类（id/name/queryUrl/homeUrl/desc）+ SEARCH_ENGINES 9 家（Google/Bing/DuckDuckGo/百度/搜狗/360/头条/Yandex/Brave）+ getEngineById（未命中回退 google）
- **B 持久化+设置切换**：AppConfig/AppConfigUpdate 增 searchEngineId（默认 'google'，fromJSON 容错读旧配置）；ConfigManager.set 处理新字段 + getSearchEngineId()；SettingsPage 导航首位新增「搜索」节（当前引擎行+「更改」弹层+单选列表，选中即保存，ic_check 复用现有图标）；omnibox onAddressInput fallback 从硬编码 Constants.DEFAULT_SEARCH_ENGINE 改为 eng.queryUrl 拼接（Constants 保留兜底）
- **C omnibox 引擎显示**：建议首行 title 拼引擎名（「百度 搜索 xx」）；OmniboxSuggestions 底部新增「搜索引擎 · 百度 | 切换」行，onSwitchEngine 回调深链 router.pushUrl 设置页搜索节（params.section='search'，aboutToAppear 读取直达 navSelection=0）

### 验证（VM 127.0.0.1:15566 实机，build_v1_hap+install_p8 链）
- 设置页搜索节全渲染：9 引擎名称+描述+queryUrl（dump .verify/p18_l8.json，截图 p18_s2.jpeg）
- 切换百度生效：UI 当前引擎=百度 + https://www.baidu.com/s?wd=（p18_l9）；config.json 落盘 "searchEngineId":"baidu"；hilog `SettingsPage searchEngine switched: baidu`
- 重启保持：应用重启后建议首行仍显示「百度 搜索」（config 跨启动持久化 ✓，p18_l25/l27）
- omnibox 引擎显示：建议首行 `百度 搜索 xx` + 底栏 `搜索引擎 · 百度`+`切换` 入口（p18_l25/p27 dump + 截图 p18_s3.jpeg）
- 证据：evidence/p18/REPORT.md + .verify/p18_*.json/jpeg

### 遗留记录
- 最终导航端到端（纯文本回车→地址栏变 baidu.com/s?wd=）受自动化环境限制未截得：uinput -K -t 只追加不清选区（输入变 about:blankzz 以 about: 前缀走 URL 分支）+ dshapp(com.oneaiterm.terminal) 反复抢前台。代码链路与数据源同源五路实证（设置 UI/建议首行/底栏/config.json/hilog 全部=baidu），待手动环境一键复验。
