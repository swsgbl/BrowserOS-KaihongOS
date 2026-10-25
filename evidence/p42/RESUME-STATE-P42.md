# P42 断点文档（RELAY-0：侦查完毕，代码未写）

任务：`D:\BrowserOS - KaihongOS\.zcode\p42_brief.md`（8 项 A-H）。基线 commit `a691112`（工作树仅 DEVPLAN.md modified + attic/ 未跟踪，干净可动手）。

## 已核实的代码落点（全部实读，勿重查）

### A loopback 绑定
- `entry/src/main/ets/service/HttpMcpTransport.ets` ~L82: `await server.listen({ address: '0.0.0.0', port: port })`（注释"qemu 端口转发需要全网卡"——P42 决策推翻：改 127.0.0.1 后 fport 仍通，hdcd 在 guest 内走 loopback）
- `entry/src/main/ets/service/WsMcpTransport.ets` ~L87: 同款 `listen({ address: '0.0.0.0' })`
- `MCPServer.ets` L62/L78 注释里的 "0.0.0.0" 同步改
- 验证：smoke 第 6 步（fport 19222→9222 隧道 POST initialize）应仍通 + 宿主直接 curl http://192.168.161.137:9222 应拒/超时（设备无 9222 映射，可配合设备内 netstat 看 127.0.0.1:9222 监听）

### B CSPRNG
- `MCPServer.ets` L313 `generateRequestId()`、L320 `generateAuthToken()` 均 Math.random
- **关键约束**：`EntryAbility.ets` L59-60 `MCPServer.start(config.mcpPort, token, config.wsPort)` 同步链。方案：generateAuthToken/generateRequestId 保持 sync 签名，内部 cryptoFramework `createRandom().generateRandomSync(len)`（WsMcpTransport 已用 @kit.CryptoArchitectureKit createMd，同 SDK 可用；写码前 harmony_api_lookup 查 generateRandomSync）。token 映射到 base62 字符表保持格式（32 字符）。
- 验证：token 格式不变（mcp_token.txt 32 字符）+ smoke 6 过。

### C type 敏感 gate
- `MCPServer.ets` handleType ~L224（L174 注册）；gate 样板 L190（navigate）/L210（click）
- `SensitiveOperationDetector.ets`：词表 sensitiveKeywords（PAYMENT/DELETE/SETTINGS_CHANGE 含 'password'）。新增 `detectType(agentId, selector, text)`——selector+text 走 detectClick 同款词表；requestConfirmation 复用（targetUrl=text, targetElement=selector）。sensitiveConfirm=false 自动放行（现有逻辑）。
- 设备验证前查 ConfigManager 默认值（L254/L319）；MCP type 敏感文本 → ConfirmDialog 挂起或 reject 证据。

### D 脱敏
- 新 `entry/src/main/ets/common/Redact.ets`：`redactSensitive(s)`，模式 `sk-[A-Za-z0-9]{8,}`、`password=...`、`"token":"..."`、连续 16+ hex，替换为 `***`
- 接线两处：①`McpJsonRpcCore.ets` tools/call 成功路径 `item.text = JSON.stringify(response.data)` 处 + 失败 message；②`AuditLogger.ets` flush() `entry.toLogString()` 每行包 redactSensitive
- 验证：MCP type text=`sk-abcdefgh12345` → 响应与 audit/*.jsonl 均含 `***`

### E 会话清理按真实时间
- 真正清理路径 `SessionManager.ets` cleanupOldSessions()（~L300）：`files.sort()` 文件名序删最旧 20%。brief 说的 L143 是索引对账序（字典倒序≈时间倒序，可保留）。
- 改法：listDir 后 load 每个 json parse startTime，升序淘汰（parse 失败排最旧）；顺手补 removeFromIndex + persistedSessions 过滤（现 cleanup 不更新索引，是既有 bug）。
- 验证：设备造 3 个不同 startTime 的 sessions/*.json → 触发清理 → 最旧被删。

### F html2canvas 本地化
- `entry/src/main/ets/protocol/JSBridgeInjector.ets` L340-349 HTML2CANVAS_LOADER：cdnjs 1.4.1
- 方案：①下载 html2canvas.min.js（宿主，先 netstat 核实代理 7892/10808）放 `entry/src/main/resources/rawfile/`；②injectBridge 改为 ArkTS 侧 `resourceManager.getRawFileContentSync('html2canvas.min.js')` 读出 → TextDecoder 解码 → `runJavaScript(源码)` 直接 eval（替换 L364 的 HTML2CANVAS_LOADER runJavaScript）。
- JSBridgeInjectorImpl 无 context——查 BrowserShell 调 injectBridge 处（需传 getHostContext().resourceManager 或全局存）；harmony_api_lookup 查 getRawFileContentSync。
- 验证：断网下 MCP screenshot 出 data:image/jpeg。
- build_api23_hap.py 查证是否整目录拷 rawfile（大概率是，无需改）。

### G isUrl localhost
- `BrowserShell.ets` L2210-2212（brief 的 2248 已偏移）：`/^(https?:\/\/)?([\w-]+\.)+[\w-]+(:\d{1,5})?(\/[\w-./?%&=]*)?$/`
- 改法：正则加 localhost|127.0.0.1 分支或前置快速通道，行为不变。

### H 发布工程
- remotes：origin=github.com/swsgbl/BrowserOS-KaihongOS.git、atomgit=atomgit.com/hongfu/BrowserOS-KaihongOS.git
- `UPSTREAM_BASELINE.md`：上游基线 commit（da5f95e/e1ee0f0/1cccd53 等）、Neo 形态声明、平台替代表（README 已在 a691112 重写，提炼）
- `tools/verify_mirrors.py`：git ls-remote 两远端 HEAD + 本地 rev-parse，三方比对；AtomGit DNS 失败→如实 UNREACHABLE。网络先 vpn-manager。
- tag `v0.1.0-alpha` 附注（A-G 全绿后打）；push 需 http.version=HTTP/1.1+代理（长期记忆）。

## 构建链（照旧）
hvigorw.bat assembleHap --mode module -p product=default --no-daemon → python tools/build_api23_hap.py（ZIP_STORED 铁律）→ 签名安装模板 tools/install_p8.py → 设备 192.168.161.137:10178。
smoke：python tools/smoke_reg.py；static：python tools/static_checks.py（P41 起 11 合规文件门禁）。

## 下棒执行顺序
1. 并行 harmony_api_lookup ×2-3（generateRandomSync / getRawFileContentSync）
2. 代码 A→G（MCPServer 批 / SessionManager / JSBridgeInjector+下载 js / BrowserShell 一行）
3. static + 构建 → build_api23 → 签名装机
4. smoke 9/9 + A-G 各一条设备证据进 evidence/p42/
5. H 三件（tag 最后）
6. git 提交（hmharness 自动 checkpoint，收尾 git log 确认）

## 红线
只在项目内读写；每项设备证据；占位=失败；每项验证 ≤3 次尝试如实记录。
