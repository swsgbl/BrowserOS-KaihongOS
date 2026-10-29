# 安全政策（Security Policy）

## 支持版本

| 版本 | 支持状态 |
|---|---|
| main（P56+）/ v0.1.0-beta | ✅ 安全修复 |
| 历史 tag（含 v0.1.0-alpha） | ❌ 请升级到 main |

## 报告漏洞

**请勿通过公开 Issue 报告安全漏洞。**

请通过 GitHub 仓库的 **Report a vulnerability**（Security  Advisories）或 AtomGit 仓库私信提交，内容包括：

- 问题类型（如内存破坏 / 凭据泄露 / 注入）
- 复现路径与影响面
- 如有，PoC 或截图

我们将在 **7 天内**确认收到、**30 天内**给出评估与修复计划；修复发布前请勿公开披露。安全修复会在 CHANGELOG 中致谢报告者（除非要求匿名）。

## 本项目的安全设计（供审计参考）

- **密钥存储**：LLM API Key 经 `@ohos.security.asset`（Asset Store Kit，硬件级安全存储）加密保管；`config.json` 落盘前一律脱敏（字段置空），磁盘上不存在明文密钥；首次启动自动完成明文→asset 的幂等迁移。
- **凭据加密（P47→P51）**：密码管理器与登录态导入的凭据由 `CredentialStore` 统一管理，**Asset Store 为主真值源**（P51 完成加密迁移）；不落明文盘。
- **MCP Session 隔离（P51 McpSessionStore）**：每个 MCP 连接独立 session——session-id 校验（未知/失效会话拒绝）+ tab ownership（会话只可操作自己开的 tab）+ 并发隔离（多 harness/客户端同时接入互不串台）；配合 McpRateLimiter 滑动窗口限流（默认 30req/10s/连接，超限 HTTP 429 / WS -32000）。
- **审计脱敏（P51 AuditRedactor）**：内部 agent 与外部 MCP 工具调用的审计输出经统一脱敏（token/key/敏感 URL 参数遮蔽）后才落盘/展示（AuditPage）。
- **连接状态真实化（P52）**：harness 连接状态不再假报 Connected——`connect()` 仅表示配置就绪，`testConnection()` 执行真实 MCP initialize 握手（HTTP 200 + serverInfo browseros_mcp）后才标记 connected 并持久化；用户可随时在 Connect 对话框复测。
- **llm_config 本地管理能力（P65）**：LLM 供应商 key 的程序化写入通道（loopback + token 信任级，与外部浏览器工具同级）。key 真值仅经 ConfigManager 同链路进 Asset Store 真加密存储，config.json 恒脱敏（llmApiKey 空）；工具响应只回掩码（sk-****后4位），审计日志经 AuditRedactor 键名脱敏（api_?key 模式）双保险。
- **设备端 MCP 服务**：HTTP（:9222）与 WebSocket（:8765）通道均要求 token 鉴权；token 每次应用冷启动轮换（CSPRNG）；仅监听本机回环（loopback only，不暴露 0.0.0.0）。
- **敏感操作确认（尽力而为的关键词层）**：导航/click/type 上的 PAYMENT/DELETE/SETTINGS 三类关键词命中触发弹窗人工确认（可配置，`sensitiveConfirm`）。客户端无法做语义级保证——关键词层只提供尽力而为的拦截，绕过（换选择器命名/间接路径）在原理上可行，不应作为唯一防线。FORM_SUBMIT 字面量档（'form'/'submit' 子串匹配）已移除（P63）：同一按钮 `#su` vs `input[type=submit]` 即可绕过，且搜索框提交是最常见的常规 agent 操作，上游 BrowserOS 亦无工具级确认档；表单提交不再触发确认。
- **网络安全**：遵循平台禁令，应用内出网仅走 https（明文 http 会被系统层瞬断）；MCP 本机回环除外。
- **无数据收集**：零遥测、零上传；历史/书签/会话仅存于应用沙盒。
- **已知边界**（如实披露）：设备侧签名当前为本地调试证书；正式分发必须替换官方发布证书并走应用市场审核流程。

## 供应链

- CI（GitHub Actions）仅执行仓库内 `tools/static_checks.py`，不引入第三方构建依赖；
- 本仓库不打包任何 SDK 二进制（构建工具链来自本机 DevEco/OpenHarmony SDK）。

## P67：设备智能体注册信任级（agent_register / device_agent_tasks）

与 llm_config 同级：**loopback + Bearer token 管理面**。

- `agent_register` / `device_agent_tasks` 走统一 `/mcp` 端点，须持有效 session（initialize→Mcp-Session-Id）与 Bearer token（files/mcp_token.txt 同源），未授权请求 401。
- 注册表 `device_agents.json` 只存 name/kind/registeredAt/lastSeen，**不含任何密钥或命令内容**；命令模板只存在于 runner 侧（VM 文件系统），应用侧不可见、不可注入。
- 任务收件箱 `files/device_agent_tasks/` 是应用沙盒私有目录，设备侧 runner 只能经 MCP 工具读写（next/complete），无直接文件系统通道。
- 结果回写截断 32KB，防止内存放大；runner 执行的命令在 VM 侧独立进程，不受应用沙盒权限放大影响。
